# Vulkan Tutorial

Vulkan [tutorial][0] written in [Odin][1].

## Introduction

This repository will follow the structure of the original tutorial. Each commit will correspond to one page or on section of the page for long chapters.

Sometimes an 'extra' commit will be added with some refactoring, commenting or feature.

## Requirements

You need to have a [Vulkan SDK][2] and the [Odin compiler][3].

## Running the project

```sh
odin run .

# or with validation layers
odin run . -define:ENABLE_VALIDATION_LAYERS=true
```

## Commits

This section contains the summary of the project commits. Follow :rabbit2: to go to the related tutorial page.

### 1.1.1: Base code [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Base_code)

GLFW initialization, window's creation and main loop setup.

### 1.1.2: Instance [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Instance)

Create and destroy the Vulkan instance.

### 1.1.3: Validation layers [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Validation_layers)

Enable `VK_LAYER_KHRONOS_validation` validation layer and setup the debug messenger.

> Here we make use of Odin's [command-line defines][4] to control the activation of the validation layers (see [here](#running-the-project)).

### 1.1.4: Physical devices and queue families [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Physical_devices_and_queue_families)

Physical device and queue families selection.

### 1.1.5: Logical device and queues [:rabbit2:](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Logical_device_and_queues)

Create the logical device and retrieve a graphics queue.



[0]: https://vulkan-tutorial.com/
[1]: https://odin-lang.org/
[2]: https://www.lunarg.com/vulkan-sdk/
[3]: https://odin-lang.org/docs/install/
[4]: https://odin-lang.org/docs/overview/#command-line-defines
