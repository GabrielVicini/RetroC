#include "LuaNetworking.h"
#include "lauxlib.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

#ifdef _WIN32
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #pragma comment(lib, "ws2_32.lib")
    typedef int socklen_t;
#else
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <fcntl.h>
    #include <errno.h>
    #define SOCKET int
    #define INVALID_SOCKET -1
    #define SOCKET_ERROR -1
    #define closesocket close
#endif

void Networking_Init(void) {
#ifdef _WIN32
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        // You might want to map this to your TraceLog
        printf("WSAStartup failed.\n");
    }
#endif
}

void Networking_Shutdown(void) {
#ifdef _WIN32
    WSACleanup();
#endif
}

static void GetAddressInfo(struct sockaddr_in *addr, const char *ip, int port) {
    memset(addr, 0, sizeof(struct sockaddr_in));
    addr->sin_family = AF_INET;
    addr->sin_port = htons((uint16_t)port);
    if (ip == NULL || strcmp(ip, "*") == 0 || strcmp(ip, "0.0.0.0") == 0) {
        addr->sin_addr.s_addr = INADDR_ANY;
    } else {
        inet_pton(AF_INET, ip, &addr->sin_addr);
    }
}

static int lua_net_tcp(lua_State *L) {
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == INVALID_SOCKET) return 0;
    lua_pushinteger(L, (lua_Integer)sock);
    return 1;
}

static int lua_net_udp(lua_State *L) {
    SOCKET sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock == INVALID_SOCKET) return 0;
    lua_pushinteger(L, (lua_Integer)sock);
    return 1;
}

static int lua_net_setNonBlocking(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    int nonblock = lua_toboolean(L, 2);
#ifdef _WIN32
    u_long mode = nonblock ? 1 : 0;
    ioctlsocket(sock, FIONBIO, &mode);
#else
    int flags = fcntl(sock, F_GETFL, 0);
    if (flags != -1) {
        flags = nonblock ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK);
        fcntl(sock, F_SETFL, flags);
    }
#endif
    return 0;
}

static int lua_net_bind(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    const char *ip = luaL_checkstring(L, 2);
    int port = (int)luaL_checkinteger(L, 3);

    struct sockaddr_in addr;
    GetAddressInfo(&addr, ip, port);

    if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_net_listen(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    int backlog = (int)luaL_optinteger(L, 2, 10);

    if (listen(sock, backlog) == SOCKET_ERROR) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_net_accept(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    SOCKET client_sock = accept(sock, (struct sockaddr*)&client_addr, &addr_len);
    if (client_sock == INVALID_SOCKET) {
        // Will fail naturally in non-blocking mode if no pending connections
        return 0;
    }

    char ip_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &client_addr.sin_addr, ip_str, INET_ADDRSTRLEN);

    lua_pushinteger(L, (lua_Integer)client_sock);
    lua_pushstring(L, ip_str);
    lua_pushinteger(L, ntohs(client_addr.sin_port));
    return 3;
}

static int lua_net_connect(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    const char *ip = luaL_checkstring(L, 2);
    int port = (int)luaL_checkinteger(L, 3);

    struct sockaddr_in addr;
    GetAddressInfo(&addr, ip, port);

    int res = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
    if (res == SOCKET_ERROR) {
#ifdef _WIN32
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            lua_pushboolean(L, 1); // Non-blocking connect in progress
            return 1;
        }
#else
        if (errno == EINPROGRESS) {
            lua_pushboolean(L, 1); // Non-blocking connect in progress
            return 1;
        }
#endif
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_net_send(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    int bytes = send(sock, data, (int)len, 0);
    if (bytes == SOCKET_ERROR) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, bytes);
    return 1;
}

static int lua_net_recv(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    int max_size = (int)luaL_optinteger(L, 2, 4096);

    char *buffer = malloc(max_size);
    if (!buffer) return 0;

    int bytes = recv(sock, buffer, max_size, 0);

    if (bytes > 0) {
        lua_pushlstring(L, buffer, bytes);
        free(buffer);
        return 1;
    } else if (bytes == 0) {
        free(buffer);
        lua_pushnil(L);
        lua_pushstring(L, "closed");
        return 2;
    } else {
        free(buffer);
#ifdef _WIN32
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
#else
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
#endif
            lua_pushnil(L);
            lua_pushstring(L, "timeout");
            return 2;
        }
        lua_pushnil(L);
        lua_pushstring(L, "error");
        return 2;
    }
}

static int lua_net_sendTo(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *ip = luaL_checkstring(L, 3);
    int port = (int)luaL_checkinteger(L, 4);

    struct sockaddr_in addr;
    GetAddressInfo(&addr, ip, port);

    int bytes = sendto(sock, data, (int)len, 0, (struct sockaddr*)&addr, sizeof(addr));
    if (bytes == SOCKET_ERROR) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, bytes);
    return 1;
}

static int lua_net_recvFrom(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    int max_size = (int)luaL_optinteger(L, 2, 4096);

    char *buffer = malloc(max_size);
    if (!buffer) return 0;

    struct sockaddr_in sender_addr;
    socklen_t addr_len = sizeof(sender_addr);

    int bytes = recvfrom(sock, buffer, max_size, 0, (struct sockaddr*)&sender_addr, &addr_len);

    if (bytes > 0) {
        char ip_str[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &sender_addr.sin_addr, ip_str, INET_ADDRSTRLEN);

        lua_pushlstring(L, buffer, bytes);
        lua_pushstring(L, ip_str);
        lua_pushinteger(L, ntohs(sender_addr.sin_port));
        free(buffer);
        return 3;
    } else {
        free(buffer);
#ifdef _WIN32
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
#else
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
#endif
            lua_pushnil(L);
            lua_pushstring(L, "timeout");
            return 2;
        }
        lua_pushnil(L);
        lua_pushstring(L, "error");
        return 2;
    }
}

static int lua_net_close(lua_State *L) {
    SOCKET sock = (SOCKET)luaL_checkinteger(L, 1);
    closesocket(sock);
    return 0;
}

void Networking_Register(lua_State *L) {
    lua_newtable(L);

    lua_pushcfunction(L, lua_net_tcp); lua_setfield(L, -2, "tcp");
    lua_pushcfunction(L, lua_net_udp); lua_setfield(L, -2, "udp");
    lua_pushcfunction(L, lua_net_setNonBlocking); lua_setfield(L, -2, "setNonBlocking");

    lua_pushcfunction(L, lua_net_bind); lua_setfield(L, -2, "bind");
    lua_pushcfunction(L, lua_net_listen); lua_setfield(L, -2, "listen");
    lua_pushcfunction(L, lua_net_accept); lua_setfield(L, -2, "accept");
    lua_pushcfunction(L, lua_net_connect); lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, lua_net_send); lua_setfield(L, -2, "send");
    lua_pushcfunction(L, lua_net_recv); lua_setfield(L, -2, "recv");
    lua_pushcfunction(L, lua_net_sendTo); lua_setfield(L, -2, "sendTo");
    lua_pushcfunction(L, lua_net_recvFrom); lua_setfield(L, -2, "recvFrom");

    lua_pushcfunction(L, lua_net_close); lua_setfield(L, -2, "close");

    lua_setglobal(L, "net");
}