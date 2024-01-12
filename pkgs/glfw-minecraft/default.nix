{ lib, glfw-wayland-minecraft, ... }:
glfw-wayland-minecraft.overrideAttrs (o: {
  patches = [
    ./suppress-wayland-errors.patch
  ];
})
