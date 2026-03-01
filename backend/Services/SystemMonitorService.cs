using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;

namespace IIS_Site_Manager.API.Services;

public class SystemMonitorService : IHostedService
{
    static PerformanceCounter? _cpuCounter;
    static PerformanceCounter? _bytesReceivedCounter;
    static PerformanceCounter? _bytesSentCounter;
    static PerformanceCounter[]? _netCounters; // Network Interface fallback (Web Service may not count ASP.NET Core)

    // Cached values - updated by background timer (PerformanceCounter needs ~1s between samples)
    double _cachedCpu;
    double _cachedBytesRecv;
    double _cachedBytesSent;
    readonly object _lock = new();
    Timer? _samplingTimer;

    public SystemMonitorService()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            try
            {
                _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                _cpuCounter.NextValue(); // First call returns 0

                // Web Service counters for IIS bandwidth (_Total = all sites)
                _bytesReceivedCounter = new PerformanceCounter("Web Service", "Bytes Received/sec", "_Total");
                _bytesSentCounter = new PerformanceCounter("Web Service", "Bytes Sent/sec", "_Total");
                _bytesReceivedCounter.NextValue();
                _bytesSentCounter.NextValue();

                // Fallback: Network Interface (total system traffic) if Web Service returns 0
                try
                {
                    var cat = new PerformanceCounterCategory("Network Interface");
                    var instances = cat.GetInstanceNames().Where(n => n != "Loopback Pseudo-Interface 1").ToArray();
                    if (instances.Length > 0)
                    {
                        _netCounters = instances.Select(i =>
                            new PerformanceCounter("Network Interface", "Bytes Total/sec", i)).ToArray();
                        foreach (var c in _netCounters) c.NextValue();
                    }
                }
                catch { }
            }
            catch { /* Ignore if not admin or IIS not installed */ }
        }
    }

    public Task StartAsync(CancellationToken ct)
    {
        // Sample every 1.5s - PerformanceCounter rate values need ~1s between calls
        _samplingTimer = new Timer(_ => SampleCounters(), null, TimeSpan.FromMilliseconds(500), TimeSpan.FromMilliseconds(1500));
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;

    void SampleCounters()
    {
        try
        {
            lock (_lock)
            {
                // Prefer WMI (works without Performance Monitor Users); fallback to PerformanceCounter
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    var wmi = GetCpuViaWmi();
                    if (wmi >= 0) _cachedCpu = wmi;
                }
                if (_cachedCpu == 0 && _cpuCounter != null)
                {
                    var v = _cpuCounter.NextValue();
                    if (v > 0) _cachedCpu = Math.Round(v, 2);
                }
                if (_bytesReceivedCounter != null && _bytesSentCounter != null)
                {
                    _cachedBytesRecv = _bytesReceivedCounter.NextValue();
                    _cachedBytesSent = _bytesSentCounter.NextValue();
                }
                // Use Network Interface if Web Service is 0 (ASP.NET Core may not be counted by Web Service)
                if (_cachedBytesRecv == 0 && _cachedBytesSent == 0 && _netCounters != null)
                {
                    var total = _netCounters.Sum(c => { try { return c.NextValue(); } catch { return 0f; } });
                    _cachedBytesRecv = total / 2; _cachedBytesSent = total / 2; // Approximate split
                }
            }
        }
        catch { }
    }

    public (double CpuPercent, double MemoryPercent, long MemoryUsed, long MemoryTotal, double BytesReceivedPerSec, double BytesSentPerSec) GetMetrics()
    {
        var memory = GetMemoryMetrics();
        lock (_lock)
            return (_cachedCpu, memory.percent, memory.used, memory.total, _cachedBytesRecv, _cachedBytesSent);
    }

    (double percent, long used, long total) GetMemoryMetrics()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var memStatus = new MEMORYSTATUSEX();
            memStatus.dwLength = (uint)Marshal.SizeOf(memStatus);
            if (GlobalMemoryStatusEx(ref memStatus))
            {
                var total = (long)memStatus.ullTotalPhys;
                var used = total - (long)memStatus.ullAvailPhys;
                var percent = total > 0 ? (double)used / total * 100 : 0;
                return (percent, used, total);
            }
        }

        return (0, 0, 0);
    }

    static double GetCpuViaWmi()
    {
        try
        {
            // Win32_PerfFormattedData_PerfOS_Processor has PercentProcessorTime for _Total
            using var searcher = new ManagementObjectSearcher(
                "SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE Name='_Total'");
            foreach (var obj in searcher.Get())
            {
                if (obj["PercentProcessorTime"] != null)
                    return Math.Round(Convert.ToDouble(obj["PercentProcessorTime"]), 2);
            }
            // Fallback: Win32_Processor LoadPercentage
            using var searcher2 = new ManagementObjectSearcher("SELECT LoadPercentage FROM Win32_Processor");
            var sum = 0; var count = 0;
            foreach (var obj in searcher2.Get())
            {
                if (obj["LoadPercentage"] != null)
                { sum += Convert.ToInt32(obj["LoadPercentage"]); count++; }
            }
            return count > 0 ? Math.Round((double)sum / count, 2) : 0;
        }
        catch { return 0; }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
