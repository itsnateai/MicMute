using System.Runtime.InteropServices;

namespace MicMute;

/// <summary>
/// Manages microphone mute state via Windows Core Audio COM APIs.
/// Also provides speaker mute control for deafen mode.
/// </summary>
internal sealed class AudioManager : IDisposable
{
    // COM GUIDs
    private static readonly Guid CLSID_MMDeviceEnumerator = new("BCDE0395-E52F-467C-8E3D-C4579291692E");
    private static readonly Guid IID_IMMDeviceEnumerator = new("A95664D2-9614-4F35-A746-DE8DB63617E6");
    private static readonly Guid IID_IAudioEndpointVolume = new("5CDF2C82-841E-4546-9722-0CF74078229A");

    // PKEY_Device_FriendlyName = {A45C254E-DF1C-4EFD-8020-67D146A850E0}, 14
    private static readonly Guid PKEY_FriendlyName_fmtid = new("A45C254E-DF1C-4EFD-8020-67D146A850E0");
    private const int PKEY_FriendlyName_pid = 14;

    // IAudioEndpointVolume vtable offsets (after IUnknown 0-2)
    private const int VT_SetMute = 14;
    private const int VT_GetMute = 15;

    // IMMDeviceEnumerator vtable
    private const int VT_EnumAudioEndpoints = 3;
    private const int VT_GetDefaultAudioEndpoint = 4;
    private const int VT_GetDevice = 5;

    // IMMDevice vtable
    private const int VT_Activate = 3;
    private const int VT_OpenPropertyStore = 4;
    private const int VT_GetId = 5;

    // IMMDeviceCollection vtable
    private const int VT_Collection_GetCount = 3;
    private const int VT_Collection_Item = 4;

    // IPropertyStore vtable
    private const int VT_PropStore_GetValue = 5;

    private nint _pAudioEndpointVolume;
    private bool _disposed;

    public bool HasEndpoint => _pAudioEndpointVolume != 0;

    /// <summary>
    /// Initialize the audio endpoint for the given device ID (empty = system default).
    /// Returns true if successful.
    /// </summary>
    public bool Initialize(string deviceId)
    {
        // Allow re-initialization even after Dispose (e.g. device hotplug)
        _disposed = false;
        Release();

        var clsid = CLSID_MMDeviceEnumerator;
        var iid = IID_IMMDeviceEnumerator;
        nint pEnum = 0;
        int hr = CoCreateInstance(ref clsid, 0, 1 /*CLSCTX_INPROC_SERVER*/,
            ref iid, out pEnum);
        if (hr < 0 || pEnum == 0)
            return false;

        nint pDev = 0;
        if (!string.IsNullOrEmpty(deviceId))
        {
            // Try specific device
            hr = ComCall_GetDevice(pEnum, deviceId, out pDev);
            if (hr < 0 || pDev == 0)
            {
                // Fall back to default
                hr = ComCall_GetDefaultEndpoint(pEnum, out pDev);
            }
        }
        else
        {
            hr = ComCall_GetDefaultEndpoint(pEnum, out pDev);
        }

        Marshal.Release(pEnum);

        if (hr < 0 || pDev == 0)
            return false;

        hr = ComCall_Activate(pDev, out nint pAEV);
        Marshal.Release(pDev);

        if (hr < 0 || pAEV == 0)
            return false;

        _pAudioEndpointVolume = pAEV;
        return true;
    }

    public void Release()
    {
        if (_pAudioEndpointVolume != 0)
        {
            Marshal.Release(_pAudioEndpointVolume);
            _pAudioEndpointVolume = 0;
        }
    }

    /// <summary>
    /// Get the current mute state. Returns null if the endpoint is invalid.
    /// </summary>
    public bool? GetMute()
    {
        if (_pAudioEndpointVolume == 0)
            return null;

        try
        {
            int hr = ComCall_GetMute(_pAudioEndpointVolume, out int muted);
            if (hr < 0)
                return null;
            return muted != 0;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Set the mute state. Returns true on success.
    /// </summary>
    public bool SetMute(bool muted)
    {
        if (_pAudioEndpointVolume == 0)
            return false;

        try
        {
            int hr = ComCall_SetMute(_pAudioEndpointVolume, muted ? 1 : 0);
            return hr >= 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Enumerate active capture (microphone) devices.
    /// </summary>
    public static List<AudioDevice> EnumerateCaptureDevices()
    {
        var devices = new List<AudioDevice>();

        var clsid = CLSID_MMDeviceEnumerator;
        var iid = IID_IMMDeviceEnumerator;
        int hr = CoCreateInstance(ref clsid, 0, 1, ref iid, out nint pEnum);
        if (hr < 0 || pEnum == 0)
            return devices;

        try
        {
            // EnumAudioEndpoints(eCapture=1, DEVICE_STATE_ACTIVE=1)
            hr = ComCall_EnumEndpoints(pEnum, out nint pCollection);
            if (hr < 0 || pCollection == 0)
                return devices;

            try
            {
                hr = ComCall_GetCount(pCollection, out int count);
                if (hr < 0)
                    return devices;

                for (int i = 0; i < count; i++)
                {
                    hr = ComCall_Item(pCollection, i, out nint pDev);
                    if (hr < 0 || pDev == 0)
                        continue;

                    try
                    {
                        string devId = GetDeviceId(pDev);
                        string name = GetDeviceFriendlyName(pDev);
                        if (!string.IsNullOrEmpty(devId) && !string.IsNullOrEmpty(name))
                            devices.Add(new AudioDevice(name, devId));
                    }
                    finally
                    {
                        Marshal.Release(pDev);
                    }
                }
            }
            finally
            {
                Marshal.Release(pCollection);
            }
        }
        finally
        {
            Marshal.Release(pEnum);
        }

        return devices;
    }

    /// <summary>
    /// Get speaker (render) mute state for deafen mode.
    /// </summary>
    public static bool GetSpeakerMute()
    {
        nint pAEV = GetDefaultRenderEndpointVolume();
        if (pAEV == 0)
            return false;
        try
        {
            int hr = ComCall_GetMuteStatic(pAEV, out int muted);
            return hr >= 0 && muted != 0;
        }
        catch
        {
            return false;
        }
        finally
        {
            Marshal.Release(pAEV);
        }
    }

    /// <summary>
    /// Set speaker (render) mute state for deafen mode.
    /// </summary>
    public static void SetSpeakerMute(bool muted)
    {
        nint pAEV = GetDefaultRenderEndpointVolume();
        if (pAEV == 0)
            return;
        try
        {
            ComCall_SetMuteStatic(pAEV, muted ? 1 : 0);
        }
        catch
        {
            // Speaker mute is best-effort
        }
        finally
        {
            Marshal.Release(pAEV);
        }
    }

    private static nint GetDefaultRenderEndpointVolume()
    {
        var clsid = CLSID_MMDeviceEnumerator;
        var iid = IID_IMMDeviceEnumerator;
        int hr = CoCreateInstance(ref clsid, 0, 1, ref iid, out nint pEnum);
        if (hr < 0 || pEnum == 0)
            return 0;

        try
        {
            // GetDefaultAudioEndpoint(eRender=0, eConsole=0)
            hr = ComCall_GetDefaultRenderEndpoint(pEnum, out nint pDev);
            if (hr < 0 || pDev == 0)
                return 0;

            try
            {
                hr = ComCall_Activate(pDev, out nint pAEV);
                return hr >= 0 ? pAEV : 0;
            }
            finally
            {
                Marshal.Release(pDev);
            }
        }
        finally
        {
            Marshal.Release(pEnum);
        }
    }

    private static string GetDeviceId(nint pDev)
    {
        // IMMDevice::GetId
        nint vtable = Marshal.ReadIntPtr(pDev);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetId * nint.Size);
        var getId = Marshal.GetDelegateForFunctionPointer<GetIdDelegate>(fnPtr);
        int hr = getId(pDev, out nint pIdStr);
        if (hr < 0 || pIdStr == 0)
            return "";
        string id = Marshal.PtrToStringUni(pIdStr) ?? "";
        Marshal.FreeCoTaskMem(pIdStr);
        return id;
    }

    private static string GetDeviceFriendlyName(nint pDev)
    {
        // IMMDevice::OpenPropertyStore(STGM_READ=0)
        nint vtable = Marshal.ReadIntPtr(pDev);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_OpenPropertyStore * nint.Size);
        var openProps = Marshal.GetDelegateForFunctionPointer<OpenPropertyStoreDelegate>(fnPtr);
        int hr = openProps(pDev, 0, out nint pStore);
        if (hr < 0 || pStore == 0)
            return "";

        try
        {
            // Build PROPERTYKEY struct
            byte[] pkeyBytes = new byte[20];
            PKEY_FriendlyName_fmtid.TryWriteBytes(pkeyBytes);
            BitConverter.TryWriteBytes(pkeyBytes.AsSpan(16), PKEY_FriendlyName_pid);

            // Allocate PROPVARIANT (24 bytes)
            nint pv = Marshal.AllocCoTaskMem(24);
            for (int i = 0; i < 24; i++)
                Marshal.WriteByte(pv, i, 0);

            try
            {
                nint storeVtable = Marshal.ReadIntPtr(pStore);
                nint getValuePtr = Marshal.ReadIntPtr(storeVtable, VT_PropStore_GetValue * nint.Size);

                nint pkeyMem = Marshal.AllocCoTaskMem(20);
                try
                {
                    Marshal.Copy(pkeyBytes, 0, pkeyMem, 20);
                    var getValue = Marshal.GetDelegateForFunctionPointer<GetValueDelegate>(getValuePtr);
                    hr = getValue(pStore, pkeyMem, pv);
                    if (hr < 0)
                        return "";

                    short vt = Marshal.ReadInt16(pv);
                    if (vt == 31) // VT_LPWSTR
                    {
                        nint pStr = Marshal.ReadIntPtr(pv, 8);
                        string name = pStr != 0 ? (Marshal.PtrToStringUni(pStr) ?? "") : "";
                        PropVariantClear(pv);
                        return name;
                    }
                    PropVariantClear(pv);
                    return "";
                }
                finally
                {
                    Marshal.FreeCoTaskMem(pkeyMem);
                }
            }
            finally
            {
                Marshal.FreeCoTaskMem(pv);
            }
        }
        finally
        {
            Marshal.Release(pStore);
        }
    }

    // COM call helpers using manual vtable dispatch

    private static int ComCall_GetDefaultEndpoint(nint pEnum, out nint pDev)
    {
        // IMMDeviceEnumerator::GetDefaultAudioEndpoint(eCapture=1, eConsole=0)
        nint vtable = Marshal.ReadIntPtr(pEnum);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetDefaultAudioEndpoint * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetDefaultEndpointDelegate>(fnPtr);
        return fn(pEnum, 1, 0, out pDev);
    }

    private static int ComCall_GetDefaultRenderEndpoint(nint pEnum, out nint pDev)
    {
        // IMMDeviceEnumerator::GetDefaultAudioEndpoint(eRender=0, eConsole=0)
        nint vtable = Marshal.ReadIntPtr(pEnum);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetDefaultAudioEndpoint * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetDefaultEndpointDelegate>(fnPtr);
        return fn(pEnum, 0, 0, out pDev);
    }

    private static int ComCall_GetDevice(nint pEnum, string deviceId, out nint pDev)
    {
        nint vtable = Marshal.ReadIntPtr(pEnum);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetDevice * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetDeviceDelegate>(fnPtr);
        return fn(pEnum, deviceId, out pDev);
    }

    private static int ComCall_EnumEndpoints(nint pEnum, out nint pCollection)
    {
        nint vtable = Marshal.ReadIntPtr(pEnum);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_EnumAudioEndpoints * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<EnumEndpointsDelegate>(fnPtr);
        return fn(pEnum, 1, 1, out pCollection); // eCapture=1, ACTIVE=1
    }

    private static int ComCall_GetCount(nint pCollection, out int count)
    {
        nint vtable = Marshal.ReadIntPtr(pCollection);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_Collection_GetCount * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetCountDelegate>(fnPtr);
        return fn(pCollection, out count);
    }

    private static int ComCall_Item(nint pCollection, int index, out nint pDev)
    {
        nint vtable = Marshal.ReadIntPtr(pCollection);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_Collection_Item * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<ItemDelegate>(fnPtr);
        return fn(pCollection, index, out pDev);
    }

    private static int ComCall_Activate(nint pDev, out nint pAEV)
    {
        nint vtable = Marshal.ReadIntPtr(pDev);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_Activate * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<ActivateDelegate>(fnPtr);
        var iidAEV = IID_IAudioEndpointVolume;
        return fn(pDev, ref iidAEV, 1, 0, out pAEV);
    }

    private int ComCall_GetMute(nint pAEV, out int muted)
    {
        nint vtable = Marshal.ReadIntPtr(pAEV);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetMute * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetMuteDelegate>(fnPtr);
        return fn(pAEV, out muted);
    }

    private int ComCall_SetMute(nint pAEV, int muted)
    {
        nint vtable = Marshal.ReadIntPtr(pAEV);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_SetMute * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<SetMuteDelegate>(fnPtr);
        return fn(pAEV, muted, 0);
    }

    private static int ComCall_GetMuteStatic(nint pAEV, out int muted)
    {
        nint vtable = Marshal.ReadIntPtr(pAEV);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_GetMute * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<GetMuteDelegate>(fnPtr);
        return fn(pAEV, out muted);
    }

    private static int ComCall_SetMuteStatic(nint pAEV, int muted)
    {
        nint vtable = Marshal.ReadIntPtr(pAEV);
        nint fnPtr = Marshal.ReadIntPtr(vtable, VT_SetMute * nint.Size);
        var fn = Marshal.GetDelegateForFunctionPointer<SetMuteDelegate>(fnPtr);
        return fn(pAEV, muted, 0);
    }

    // COM delegates
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetDefaultEndpointDelegate(nint pThis, int dataFlow, int role, out nint ppEndpoint);

    [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    private delegate int GetDeviceDelegate(nint pThis, [MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out nint ppDevice);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int EnumEndpointsDelegate(nint pThis, int dataFlow, int stateMask, out nint ppDevices);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetCountDelegate(nint pThis, out int count);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int ItemDelegate(nint pThis, int nDevice, out nint ppDevice);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int ActivateDelegate(nint pThis, ref Guid iid, int dwClsCtx, nint pActivationParams, out nint ppInterface);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetMuteDelegate(nint pThis, out int pbMute);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int SetMuteDelegate(nint pThis, int bMute, nint pguidEventContext);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetIdDelegate(nint pThis, out nint ppwstrId);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int OpenPropertyStoreDelegate(nint pThis, int stgmAccess, out nint ppProperties);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetValueDelegate(nint pThis, nint key, nint pv);

    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(ref Guid rclsid, nint pUnkOuter, int dwClsContext, ref Guid riid, out nint ppv);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(nint pvar);

    public void Dispose()
    {
        if (!_disposed)
        {
            Release();
            _disposed = true;
        }
    }
}

internal sealed record AudioDevice(string Name, string Id);
