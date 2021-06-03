Shader "Custom/CustomShadowMap" {
    Properties {
        _Diffuse ("Diffuse", Color) = (1, 1, 1, 1)
		_Specular ("Specular", Color) = (1, 1, 1, 1)
		_Gloss ("Gloss", Range(8.0, 256)) = 20
        _Samples ("Samples", Range(8, 256)) = 16
        _LightSize ("LightSize", Range(0, 1)) = 0.05
        _LightFrustumWidth ("LightFrustumWidth", Range(0, 100)) = 10
        _NearPlane ("NearPlane", Range(0, 8)) = 1
    }
    SubShader {
        Tags { "RenderType"="Opaque" }
        Pass {
            CGPROGRAM
            
            #pragma multi_compile_fwdbase

            #pragma vertex vert
            #pragma fragment frag

            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            
            fixed4 _Diffuse;
            fixed4 _Specular;
            float _Gloss;
            int _Samples;
            float _LightSize;
            float _LightFrustumWidth;
            float _NearPlane;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float4 worldPos : TEXCOORD1;
                float4 shadowCoord : TEXCOORD2;
            };

            uniform float4x4 _worldToShadow;
            uniform sampler2D _shadowMapTexture;
            uniform float4 _shadowMapTexture_TexelSize;
            uniform float _shadowStrength;
            uniform float _shadowBias;
            uniform int _filterSize;
            uniform int _shadowType;

            float2 poissonDisk[32];
  
            float rand2to1(float2 uv)
            {
                float a = 12.9898;
                float b = 78.233;
                float c = 43758.5453;
                float dt = mul(uv.xy, float2(a, b));
                float sn = fmod(dt, UNITY_PI);
                return frac(sin(sn) * c);
            }

            void poissonDiskSamples(float2 randomSeed)
            {
                float numSampes = _Samples;
                float numRings = 10;
                float angleStep = UNITY_TWO_PI * numRings / numSampes;
                float invNumSamples = 1.0 / numSampes;
            
                float angle = rand2to1(randomSeed) * UNITY_TWO_PI;
                float radius = invNumSamples;
                float radiusStep = radius;
            
                for(int i = 0; i < numSampes; i++)
                {
                    poissonDisk[i] = float2(cos(angle), sin(angle) * pow(radius, 0.75));
                    radius += radiusStep;
                    angle += angleStep;
                }
            }

            v2f vert(a2v v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.shadowCoord = mul(_worldToShadow, o.worldPos);
                return o;
            }

            float hardShadow(float depth, float2 uv)
            {
                float4 orignDepth = tex2D(_shadowMapTexture, uv);
                float sampleDepth = DecodeFloatRGBA(orignDepth);
                return (sampleDepth + _shadowBias) < depth ? _shadowStrength : 1;
            }

            float pcf(float depth, float2 uv, int filterSize)
            {
                float shadow = 0.0;
                int halfSize = max(0, (filterSize - 1) / 2);
                for(int i = -halfSize; i <= halfSize; ++i)
                {
                    for(int j = -halfSize; j < halfSize; ++j)
                    {
                        float4 orignDepth = tex2D(_shadowMapTexture, uv + float2(i, j) * _shadowMapTexture_TexelSize.xy);
                        float sampleDepth = DecodeFloatRGBA(orignDepth);
                        shadow += (sampleDepth + _shadowBias) < depth ? _shadowStrength : 1;
                    }
                }
                return shadow / (filterSize * filterSize);
            }

            float pcfSample(float depth, float2 uv, float filterSize)
            {
                float shadow = 0.0;
                int numSamples = _Samples;
    
                for(int i  = 0; i < numSamples; ++i)
                {
                    float4 orignDepth = tex2D(_shadowMapTexture, uv + poissonDisk[i] *  filterSize);
                    float sampleDepth = DecodeFloatRGBA(orignDepth);
                    shadow += (sampleDepth + _shadowBias) < depth ? _shadowStrength : 1;
                }

                for(int i  = 0; i < numSamples; ++i)
                {
                    float4 orignDepth = tex2D(_shadowMapTexture, uv - poissonDisk[i] * filterSize);
                    float sampleDepth = DecodeFloatRGBA(orignDepth);
                    shadow += (sampleDepth + _shadowBias) < depth ? _shadowStrength : 1;
                }

                return shadow / (2.0 * numSamples);
                
            }

            float findBlocker(float depth, float2 uv)
            {
                int blockerSearchNumSamples = _Samples;
                float lightSizeUV = _LightSize / _LightFrustumWidth;
                float searchRadius = lightSizeUV * (depth - _NearPlane) / depth;
                float blockerDepthSum = 0.0;
                int numBlockers = 0;
                for(int i = 0; i < blockerSearchNumSamples; i++)
                {
                    float4 orignDepth = tex2D(_shadowMapTexture, uv + poissonDisk[i] *  searchRadius);
                    float sampleDepth = DecodeFloatRGBA(orignDepth);

                    if(sampleDepth < depth)
                    {
                        blockerDepthSum += sampleDepth;
                        numBlockers++;
                    }
                }
                if(numBlockers == 0)
                {
                    return -1.0;
                }
                return blockerDepthSum / numBlockers;
            }

            float pcss(float depth, float2 uv)
            {

                //1. 计算Blocker平均深度
                poissonDiskSamples(uv);
                float avgBlockerDepth = findBlocker(depth, uv);
                if(avgBlockerDepth == -1.0)
                {
                    return 1.0;
                }

                //2. 计算filter大小
                //计算影子大小
                float penumbraRatio = (depth - avgBlockerDepth) / avgBlockerDepth * _LightSize;
                //通过影子大小反过来计算在ShadowMap上的filter大小
                float filterSize = penumbraRatio * _NearPlane / depth;

                //3. 做PCF
                return pcfSample(depth, uv, filterSize);
                
            }

            float vssm(float depth, float2 uv)
            {
                float4 depthTexture = tex2D(_shadowMapTexture, uv);

                float d1 = depthTexture.r;
                float d2 = depthTexture.g;
                float variance = clamp(d2 - d1 * d1, 0, 1);
               
                float delta = depth - d1;
                if((d1 + _shadowBias) < depth)
                {
                    float p1 = variance;
                    float p2 = variance + delta * delta;
                    float p = p1 / p2;
                    float amount = 0.05;
                    p = clamp((p - amount) / (1 - amount), 0, 1);
                    float shadowIntensity = 1 - p;
                    return 1 - shadowIntensity * (1 - _shadowStrength);
                } else
                {
                    return 1.0;
                }
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed3 worldNormal = normalize(i.worldNormal);
                fixed3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
                
                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz;
                fixed3 diffuse = _LightColor0.rgb * _Diffuse.rgb * max(0, dot(worldNormal, worldLightDir));
                fixed3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
                fixed3 halfDir = normalize(worldLightDir + viewDir);
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(worldNormal, halfDir)), _Gloss);
                fixed atten = 1.0;
                
                float2 uv = i.shadowCoord.xy / i.shadowCoord.w;
                uv = uv * 0.5 + 0.5;
                
                float depth = i.shadowCoord.z / i.shadowCoord.w;
                #if defined(SHADER_TARGET_GLSL)
                    depth = depth * 0.5 + 0.5;    
                #elif defined(UNITY_REVERSED_Z)
                    depth = 1 - depth;      
                #endif
                
                float shadow = 1.0;
                if(_shadowType == 1)
                {
                    shadow = hardShadow(depth, uv);
                } else if(_shadowType == 2)
                {
                    shadow = pcf(depth, uv, _filterSize);
                } else if(_shadowType == 3)
                {
                    shadow = pcss(depth, uv);
                } else if(_shadowType == 4)
                {
                    shadow = vssm(depth, uv);
                }
               
                return fixed4(ambient + (diffuse + specular) * shadow * atten, 1.0);
            }

            ENDCG
        }
    }
    FallBack "Diffuse"
}