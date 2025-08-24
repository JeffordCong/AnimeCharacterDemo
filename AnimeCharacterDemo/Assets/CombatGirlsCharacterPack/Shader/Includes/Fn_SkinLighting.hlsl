#ifndef SKIN_LIGHTING_INCLUDE
#define SKIN_LIGHTING_INCLUDE

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#include "ShadingModel.hlsl"
#include "Fn_Lighting.hlsl"


float3 SkinIndirect(float3 DiffuseColor, float3 SpecularColor, float3 PositionWS, float3 V,
                    float3 N, float3 SH, half occlusion, float Lube0Roughness, float Lube1Roughness, float LubeMix,
                    float EnvRoation, float mainShadow)
{
    float Roughness = (Lube0Roughness + Lube1Roughness) * 0.5;

    half3 R = reflect(-V, N);
    R = RotateDirection(R, EnvRoation);
    float NoV = saturate(abs(dot(N, V)) + 0.001);

    float diffuseAO = AOMultiBounce(DiffuseColor, occlusion);
    float specularAO = AOMultiBounce(SpecularColor, occlusion);
    specularAO = GetSpecularOcclusion(NoV, Roughness, specularAO);

    float3 diffuse = DiffuseColor * SH * diffuseAO;
    float3 lube0spcular = EnvSpecularDFG(R, SpecularColor, PositionWS, 
                                         NoV, occlusion, Lube0Roughness);
    float3 lube1spcular = EnvSpecularDFG(R, SpecularColor, PositionWS, 
                                         NoV, occlusion, Lube1Roughness);

    float3 specular = lerp(lube0spcular, lube1spcular, 1 - LubeMix) * specularAO;

    // 消弱背面的IBL
    specular = lerp(specular * 0.3f, specular, mainShadow);

    float3 c = diffuse + specular;
    return c;
}

float3 SkinDirect(Texture2D _SSSLUTMAP, SamplerState sampler_SSSLUTMAP, float3 DiffuseColor, float3 SpecularColor,
                  float3 V, float3 N, float3 N_blur, float3 L, float3 lightColor, float atten, float3 mainShadowColor,
                  float Lube0Roughness,
                  float Lube1Roughness, float LubeMix, float Curvature)
{
    float3 H = normalize(L + V);
    float NoL = dot(N, L) * 0.5 + 0.5;
    float NoL_Blur = dot(N_blur, L) * 0.5 + 0.5;
    float NoL_Specular = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float NoV = saturate(abs(dot(N, V)) + 0.001);
    float VoH = saturate(dot(V, H));

    float NoL_R = NoL_Blur;
    float NoL_G = lerp(NoL_Blur, NoL, 0.6);
    float NoL_B = lerp(NoL_Blur, NoL, 0.2);

    float3 lutMap_R = SAMPLE_TEXTURE2D(_SSSLUTMAP, sampler_SSSLUTMAP, float2(NoL_R,Curvature));
    float3 lutMap_G = SAMPLE_TEXTURE2D(_SSSLUTMAP, sampler_SSSLUTMAP, float2(NoL_G,Curvature));
    float3 lutMap_B = SAMPLE_TEXTURE2D(_SSSLUTMAP, sampler_SSSLUTMAP, float2(NoL_B,Curvature));
    float3 lutMap = (lutMap_R + lutMap_G + lutMap_B) / 3;

    float3 radiance_Diffuse = lutMap * lightColor * mainShadowColor;
    float3 radiance_Specular = NoL_Specular * lightColor * atten;

    float3 specular = DualSpecularGGX(Lube0Roughness, Lube1Roughness, LubeMix, SpecularColor, NoH, NoV, VoH,
                                      NoL_Specular);
    specular *= radiance_Specular;

    float3 diffuse = Diffuse_Lambert_UE4(DiffuseColor) * radiance_Diffuse;
    float3 c = specular + diffuse;

    return c * UNITY_PI;
}


float3 SkinLighting(Texture2D _SSSLUTMAP, SamplerState sampler_SSSLUTMAP, float3 DiffuseColor, float3 SpecularColor,
                    float3 viewWS, float3 positionWS, float3 normalWS, float3 N_blur,
                    float Lube0Roughness, float Lube1Roughness, float LubeMix, float ao,
                    float EnvRotation, float SSSRange, float SSSPower)
{
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light light = GetMainLight(shadowCoord, positionWS, 1);
    float mainShadow = saturate(light.shadowAttenuation + 0.2);
    float3 mainShadowColor = lerp(float3(0.11, 0.025, 0.012), float3(1, 1, 1), mainShadow);
    float atten = mainShadowColor * light.distanceAttenuation;

    float curvature = GetCurvature(SSSRange, SSSPower, normalWS, positionWS);
    float3 directLighting = SkinDirect(_SSSLUTMAP, sampler_SSSLUTMAP, DiffuseColor,
                                       SpecularColor, viewWS, normalWS, N_blur, light.direction, light.color, atten,
                                       mainShadowColor, Lube0Roughness, Lube1Roughness, LubeMix, curvature);

    float3 indirectLighting;
    {
        float3 sh = SampleSH(normalWS);
        indirectLighting = SkinIndirect(DiffuseColor, SpecularColor, positionWS,
                                        viewWS, normalWS, sh, ao, Lube0Roughness, Lube1Roughness, LubeMix,
                                        EnvRotation, light.shadowAttenuation);
    }

    float3 c = directLighting + indirectLighting;
    /**
        #if defined(_ADDITIONAL_LIGHTS)
        uint pixelLightCount = GetAdditionalLightsCount();
    
        #if USE_FORWARD_PLUS
        for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
        {
            FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK
    
            Light light = GetAdditionalLight(lightIndex, positionWS);
            {
                    atten = light.distanceAttenuation * light.shadowAttenuation;
                    c += PBRDirect_UE4(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                                       light.color, atten, roughness);
            }
        }
        #endif
    
        LIGHT_LOOP_BEGIN(pixelLightCount)
             Light light = GetAdditionalLight(lightIndex, positionWS);
            {
      
                    atten = light.distanceAttenuation * light.shadowAttenuation;
                    c += PBRDirect_UE4(DiffuseColor, SpecularColor, viewWS, normalWS, light.direction,
                                               light.color, atten, roughness);
                
    
            }
        LIGHT_LOOP_END
        #endif
    **/
    return c;
}


#endif
