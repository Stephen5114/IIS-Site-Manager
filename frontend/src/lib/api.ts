function getApiBase(): string {
  const envUrl = process.env.NEXT_PUBLIC_API_URL?.trim();
  if (envUrl) return envUrl;
  // Dev (port 3000): backend on 5032; IIS/production: use relative path (same origin)
  if (typeof window !== 'undefined') {
    if (window.location.port === '3000') return 'http://localhost:5032';
    return ''; // relative URL -> /api/* always works for same-origin
  }
  return 'http://localhost:5032';
}
const API_BASE = getApiBase();

export interface SystemMetrics {
  cpuUsagePercent: number;
  memoryUsagePercent: number;
  memoryUsedBytes: number;
  memoryTotalBytes: number;
  bytesReceivedPerSec: number;
  bytesSentPerSec: number;
  bytesTotalPerSec: number;
  timestamp: string;
}

export interface CreateSiteRequest {
  siteName: string;
  domain: string;
  physicalPath: string;
  appPoolName?: string;
  port?: number;
}

export interface IISSite {
  id: number;
  name: string;
  state: string;
  bindings: string[];
  physicalPath: string;
}

export async function fetchMetrics(): Promise<SystemMetrics> {
  const res = await fetch(`${API_BASE}/api/metrics`);
  if (!res.ok) throw new Error('Failed to fetch metrics');
  return res.json();
}

export async function fetchSites(): Promise<IISSite[]> {
  const res = await fetch(`${API_BASE}/api/sites`);
  if (!res.ok) return [];
  return res.json();
}

export async function createSite(data: CreateSiteRequest): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${API_BASE}/api/sites`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      siteName: data.siteName,
      domain: data.domain,
      physicalPath: data.physicalPath,
      appPoolName: data.appPoolName ?? 'DefaultAppPool',
      port: data.port ?? 80,
    }),
  });
  return res.json();
}
