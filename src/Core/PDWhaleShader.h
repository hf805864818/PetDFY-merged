//
//  PDWhaleShader.h — Whale.metal 内嵌副本（build.96）
//
//  为什么内嵌：着色器原先只从「素材根/Whale.metal」读取，而素材根随版本
//  在 /var/mobile/Xfy 与 /Library/Application Support/PetDFY.bundle 之间漂移；
//  一旦读不到，管线为 nil，draw 仍会提交 -> AGX 在 drawIndexedPrimitives
//  内空指针崩溃（本机 2026-11-28 19:35 两次 SpringBoard 崩溃即此路径）。
//  内嵌源码后，任何磁盘布局都不会再导致管线缺失。
//
#pragma once

static const char *kPDWhaleShaderSource =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct Varying { float4 position [[position]]; float2 uv; float2 stage; };\n"
    "struct Appearance { float4 tint; float alpha; float pad0; float pad1; float pad2; float4 clipX; float4 clipY; float4 clipRect; };\n"
    "vertex Varying whaleVertex(uint i [[vertex_id]],\n"
    "    const device float2 *positions [[buffer(0)]],\n"
    "    const device float2 *uvs [[buffer(1)]],\n"
    "    constant float4 &space [[buffer(2)]]) {\n"
    "    float2 p=(positions[i]+space.zw)/space.xy;\n"
    "    return {float4(p.x*2-1,1-p.y*2,0,1),uvs[i],positions[i]};\n"
    "}\n"
    "fragment float4 whaleFragment(Varying in [[stage_in]],\n"
    "    texture2d<float> image [[texture(0)]], sampler linearSampler [[sampler(0)]],\n"
    "    constant Appearance &look [[buffer(0)]]) {\n"
    "    if(look.clipX.w>0.5){\n"
    "        float3 p=float3(in.stage,1);\n"
    "        float2 q=float2(dot(look.clipX.xyz,p),dot(look.clipY.xyz,p));\n"
    "        if(any(q<look.clipRect.xy)||any(q>look.clipRect.zw))discard_fragment();\n"
    "    }\n"
    "    float4 c=image.sample(linearSampler,in.uv);\n"
    "    c.rgb=mix(c.rgb,c.rgb*look.tint.rgb,look.tint.a);\n"
    "    return c*look.alpha;\n"
    "}\n"
    "\n"
    "// Draw only the assembled figure's alpha into a small offscreen surface. A\n"
    "// Gaussian blur of this mask produces an outline that follows the actual\n"
    "// costume, pose and drag transform instead of a screen-space radial blob.\n"
    "fragment float4 whaleSilhouetteFragment(Varying in [[stage_in]],\n"
    "    texture2d<float> image [[texture(0)]], sampler linearSampler [[sampler(0)]],\n"
    "    constant Appearance &look [[buffer(0)]]) {\n"
    "    if(look.clipX.w>0.5){\n"
    "        float3 p=float3(in.stage,1);\n"
    "        float2 q=float2(dot(look.clipX.xyz,p),dot(look.clipY.xyz,p));\n"
    "        if(any(q<look.clipRect.xy)||any(q>look.clipRect.zw))discard_fragment();\n"
    "    }\n"
    "    float alpha=image.sample(linearSampler,in.uv).a*look.alpha;\n"
    "    return float4(alpha,alpha,alpha,alpha);\n"
    "}\n"
;
