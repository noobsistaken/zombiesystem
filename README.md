# Zombie Game

**Author:** noobs

A high-performance zombie survival game featuring a custom entity system capable of handling 200+ zombies with minimal lag.

## Key Features

*   **Custom Entity Engine:** Uses spatial hashing and steering behaviors instead of default Humanoids for max performance.
*   **Client-Side Rendering:** Server handles data, client handles visuals (BulkMoveTo) to save bandwidth.
*   **Optimized Networking:** 10Hz snapshot interpolation system.
*   **Lag Free:** Runs at ~3% CPU usage on the client with 200 zombies.

## Controls

*   **WASD:** Move
*   **Mouse:** Look/Aim
*   **Left Click:** Shoot

## Setup

1.  Open the project in Roblox Studio (via Rojo).
2.  Press **Play**.