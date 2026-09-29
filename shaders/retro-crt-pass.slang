#language slang 2026
// Returns the picture unchanged. crt-live and the crt-* monitor pipelines use it
// as their single group: kitty requires every pipeline file to contain a group,
// and a group is also how a pipeline asks for a redraw clock (animation_step).

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    return color;
}
