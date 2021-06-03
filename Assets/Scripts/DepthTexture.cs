using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class DepthTexture : MonoBehaviour
{
    public Shader depthTextureShader;
    public ComputeShader blurShader;
    public Light dirLight;

    [Range(0, 1)] public float shadowStrength;
    [Range(0, 2)] public float shadowBias;
    [Range(3, 15)] public int filterSize;

    public enum ShadowResolution
    {
        Low = 1,
        Middle = 2,
        High = 4, 
        VeryHigh = 8,
    }

    public enum ShadowType
    {
        HardShadow = 1,
        PCF = 2,
        PCSS = 3,
        VSSM = 4,
    }

    public ShadowResolution shadowResolution = ShadowResolution.Low;
    public ShadowType shadowType = ShadowType.HardShadow;

    private Camera _lightCamera;
    private RenderTexture _texture;
    private RenderTexture _blurTexture;

    private const string LightCameraName = "Light Camera";

    private ShadowResolution _cachedResolution = ShadowResolution.Low;

    private static readonly int ShadowBiasID = Shader.PropertyToID("_shadowBias");

    private static readonly int WorldToShadowID = Shader.PropertyToID("_worldToShadow");

    private static readonly int ShadowStrengthID = Shader.PropertyToID("_shadowStrength");

    private static readonly int ShadowMapTextureID = Shader.PropertyToID("_shadowMapTexture");

    private static readonly int ShadowTypeID = Shader.PropertyToID("_shadowType");

    private static readonly int FilterSizeID = Shader.PropertyToID("_filterSize");
    // Start is called before the first frame update
    void Start()
    {
        _cachedResolution = shadowResolution;
        _lightCamera = CreateLightCamera();
        if (!_lightCamera.targetTexture)
        {
            _lightCamera.targetTexture = CreateTexture((int) shadowResolution);
        }
    }

    // Update is called once per frame
    void Update()
    {
        UpdateRenderTexture();
        _lightCamera.targetTexture = _texture;
     
        var cameraTransform = _lightCamera.transform;
        var lightTransform = dirLight.gameObject.transform;

        cameraTransform.position = lightTransform.position;
        cameraTransform.rotation = lightTransform.rotation;
        cameraTransform.localScale = lightTransform.localScale;
        
        _lightCamera.RenderWithShader(depthTextureShader, "");

        if (shadowType == ShadowType.VSSM)
        {
            for (int i = 0; i < 7; ++i)
            {
                blurShader.SetTexture(0, "Read", _texture);
                blurShader.SetTexture(0, "Result", _blurTexture);
                blurShader.Dispatch(0, _texture.width / 8, _texture.height / 8, 1);
                
                Swap(ref _texture, ref _blurTexture);
            }
        }

        Shader.SetGlobalFloat(ShadowBiasID, shadowBias);
        Matrix4x4 projectionMatrix = GL.GetGPUProjectionMatrix(_lightCamera.projectionMatrix, false);
        Matrix4x4 viewMatrix = _lightCamera.worldToCameraMatrix;
        Shader.SetGlobalMatrix(WorldToShadowID, projectionMatrix * viewMatrix);
        Shader.SetGlobalFloat(ShadowStrengthID, shadowStrength);
        Shader.SetGlobalInt(ShadowTypeID, (int)shadowType);
        Shader.SetGlobalInt(FilterSizeID, filterSize);
        Shader.SetGlobalTexture(ShadowMapTextureID, _texture);
        
    }

    void UpdateRenderTexture()
    {
        if (_texture  && _cachedResolution != shadowResolution)
        {
            DestroyImmediate(_texture);
            _texture = null;
        }

        if (!_texture)
        {
            _texture = CreateTexture((int) shadowResolution);
            _blurTexture = CreateTexture((int) shadowResolution);
        }
        _cachedResolution = shadowResolution;
    }

    private Camera CreateLightCamera()
    {
        Camera lightCamera = null;
        var lightCameraObj = GameObject.Find(LightCameraName);
        if (lightCameraObj != null)
        {
            lightCamera = lightCameraObj.GetComponent<Camera>();
            ResetCamera(ref lightCamera);
        }
        else
        {
            lightCameraObj = new GameObject(LightCameraName);
            lightCamera = lightCameraObj.AddComponent<Camera>();
            ResetCamera(ref lightCamera);
        }
        return lightCamera;
    }

    private void ResetCamera(ref Camera lightCamera)
    {
        lightCamera.backgroundColor = Color.white;
        lightCamera.clearFlags = CameraClearFlags.SolidColor;
        lightCamera.orthographic = true;
        lightCamera.orthographicSize = 6f;
        lightCamera.nearClipPlane = 0.3f;
        lightCamera.farClipPlane = 20f;
        lightCamera.enabled = false;
        lightCamera.allowMSAA = false;
        lightCamera.allowHDR = false;
        lightCamera.cullingMask = -1;
    }

    private RenderTexture CreateTexture(int resolution)
    {
        const RenderTextureFormat format = RenderTextureFormat.RGFloat;
        RenderTexture rt = new RenderTexture(512 * resolution, 512 * resolution, 24, format)
        {
            hideFlags = HideFlags.DontSave,
            enableRandomWrite = transform,
            filterMode = FilterMode.Bilinear
        };
        rt.Create();
        return rt;
    }

    void Swap<T>(ref T a, ref T b)
    {
        T temp = a;
        a = b;
        b = temp;
    }

}
