#include "engine/App.h"

int main(void) {
    AppEngine app = {0};

    // Pass its address to be initialized
    App_Init(&app, "Vanguard", 640, 360);

    while (!WindowShouldClose()) {
        App_Update(&app);
        App_Render(&app);
    }

    App_Shutdown(&app);

    return 0;
}