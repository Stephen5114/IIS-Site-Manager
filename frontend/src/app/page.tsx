'use client';

import { useEffect, useState } from 'react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from 'recharts';
import {
  fetchMetrics,
  fetchSites,
  createSite,
  type SystemMetrics,
  type IISSite,
  type CreateSiteRequest,
} from '@/lib/api';

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
}

export default function Home() {
  const [metrics, setMetrics] = useState<SystemMetrics | null>(null);
  const [metricsHistory, setMetricsHistory] = useState<{ time: string; cpu: number; ram: number; bandwidth: number }[]>([]);
  const [sites, setSites] = useState<IISSite[]>([]);
  const [loading, setLoading] = useState(true);
  const [createStatus, setCreateStatus] = useState<{ type: 'success' | 'error'; msg: string } | null>(null);
  const [form, setForm] = useState<CreateSiteRequest>({
    siteName: '',
    domain: '',
    physicalPath: '',
    appPoolName: 'DefaultAppPool',
    port: 80,
  });

  useEffect(() => {
    const load = async () => {
      try {
        const [m, s] = await Promise.all([fetchMetrics(), fetchSites()]);
        setMetrics(m);
        setSites(s);
        setMetricsHistory((prev) => {
          const next = [
            ...prev.slice(-59),
            {
              time: new Date().toLocaleTimeString(),
              cpu: m.cpuUsagePercent,
              ram: m.memoryUsagePercent,
              bandwidth: m.bytesTotalPerSec ?? 0,
            },
          ];
          return next.length > 60 ? next.slice(-60) : next;
        });
      } catch {
        setMetrics(null);
        setSites([]);
      } finally {
        setLoading(false);
      }
    };

    load();
    const id = setInterval(load, 3000);
    return () => clearInterval(id);
  }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreateStatus(null);
    try {
      const result = await createSite(form);
      setCreateStatus({ type: result.success ? 'success' : 'error', msg: result.message });
      if (result.success) {
        setForm({ siteName: '', domain: '', physicalPath: '', appPoolName: 'DefaultAppPool', port: 80 });
        const s = await fetchSites();
        setSites(s);
      }
    } catch (err) {
      setCreateStatus({ type: 'error', msg: 'Request failed' });
    }
  };

  const pieData = metrics
    ? [
        { name: 'Used', value: metrics.memoryUsagePercent, color: '#6366f1' },
        { name: 'Free', value: 100 - metrics.memoryUsagePercent, color: '#e2e8f0' },
      ]
    : [];

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans">
      <header className="border-b border-slate-800 bg-slate-900/80 backdrop-blur">
        <div className="mx-auto max-w-7xl px-4 py-4 sm:px-6 lg:px-8">
          <h1 className="text-xl font-bold tracking-tight">IIS Site Manager</h1>
          <p className="mt-1 text-sm text-slate-400">Create sites · Monitor CPU, RAM & Bandwidth</p>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Metrics Section */}
        <section className="mb-10">
          <h2 className="mb-4 text-lg font-semibold text-slate-200">System Monitor</h2>
          {loading && !metrics ? (
            <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-8 text-center text-slate-400">
              Loading metrics...
            </div>
          ) : metrics ? (
            <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-7">
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">CPU Usage</p>
                <p className="mt-1 text-2xl font-bold text-emerald-400">{metrics.cpuUsagePercent.toFixed(1)}%</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">RAM Usage</p>
                <p className="mt-1 text-2xl font-bold text-indigo-400">{metrics.memoryUsagePercent.toFixed(1)}%</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">Memory Used</p>
                <p className="mt-1 text-2xl font-bold">{formatBytes(metrics.memoryUsedBytes)}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">Memory Total</p>
                <p className="mt-1 text-2xl font-bold">{formatBytes(metrics.memoryTotalBytes)}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">Bandwidth (Total)</p>
                <p className="mt-1 text-2xl font-bold text-cyan-400">{formatBytes(metrics.bytesTotalPerSec ?? 0)}/s</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">Received</p>
                <p className="mt-1 text-2xl font-bold text-amber-400">{formatBytes(metrics.bytesReceivedPerSec ?? 0)}/s</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
                <p className="text-sm text-slate-400">Sent</p>
                <p className="mt-1 text-2xl font-bold text-rose-400">{formatBytes(metrics.bytesSentPerSec ?? 0)}/s</p>
              </div>
            </div>
          ) : (
            <div className="rounded-xl border border-amber-900/50 bg-amber-950/30 p-8 text-center text-amber-200">
              Unable to connect to API. Ensure backend is running.
            </div>
          )}

          {metricsHistory.length > 0 && (
            <>
              <div className="mt-6 rounded-xl border border-slate-800 bg-slate-900/50 p-4">
                <p className="mb-3 text-sm text-slate-400">CPU & RAM over time (last 60 samples)</p>
                <div className="h-48">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={metricsHistory}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                      <XAxis dataKey="time" stroke="#94a3b8" fontSize={11} />
                      <YAxis stroke="#94a3b8" domain={[0, 100]} unit="%" />
                      <Tooltip
                        contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #334155', borderRadius: '8px' }}
                      />
                      <Area type="monotone" dataKey="cpu" stroke="#10b981" fill="#10b981" fillOpacity={0.2} />
                      <Area type="monotone" dataKey="ram" stroke="#6366f1" fill="#6366f1" fillOpacity={0.2} />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>
              <div className="mt-6 rounded-xl border border-slate-800 bg-slate-900/50 p-4">
                <p className="mb-3 text-sm text-slate-400">IIS Bandwidth over time (last 60 samples)</p>
                <div className="h-48">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={metricsHistory}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                      <XAxis dataKey="time" stroke="#94a3b8" fontSize={11} />
                      <YAxis stroke="#94a3b8" tickFormatter={(v) => formatBytes(v)} />
                      <Tooltip
                        contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #334155', borderRadius: '8px' }}
                        formatter={(v: number | undefined) => [v != null ? formatBytes(v) + '/s' : '-', 'Bandwidth']}
                      />
                      <Area type="monotone" dataKey="bandwidth" stroke="#06b6d4" fill="#06b6d4" fillOpacity={0.2} />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </>
          )}

          {pieData.length > 0 && (
            <div className="mt-6 flex flex-wrap gap-6">
              <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-4">
                <p className="mb-2 text-sm text-slate-400">RAM Distribution</p>
                <ResponsiveContainer width={180} height={180}>
                  <PieChart>
                    <Pie data={pieData} cx="50%" cy="50%" innerRadius={50} outerRadius={80} paddingAngle={2} dataKey="value">
                      {pieData.map((entry, i) => (
                        <Cell key={i} fill={entry.color} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(v: number | undefined) => (v != null ? `${v.toFixed(1)}%` : '-')} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
        </section>

        {/* Create IIS Site */}
        <section className="mb-10">
          <h2 className="mb-4 text-lg font-semibold text-slate-200">Create IIS Site</h2>
          <form onSubmit={handleCreate} className="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label className="mb-1 block text-sm text-slate-400">Site Name</label>
                <input
                  type="text"
                  required
                  value={form.siteName}
                  onChange={(e) => setForm((f) => ({ ...f, siteName: e.target.value }))}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  placeholder="MySite"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm text-slate-400">Domain</label>
                <input
                  type="text"
                  required
                  value={form.domain}
                  onChange={(e) => setForm((f) => ({ ...f, domain: e.target.value }))}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  placeholder="example.com"
                />
              </div>
              <div className="sm:col-span-2">
                <label className="mb-1 block text-sm text-slate-400">Physical Path</label>
                <input
                  type="text"
                  required
                  value={form.physicalPath}
                  onChange={(e) => setForm((f) => ({ ...f, physicalPath: e.target.value }))}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  placeholder="C:\inetpub\wwwroot\mysite"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm text-slate-400">App Pool</label>
                <input
                  type="text"
                  value={form.appPoolName}
                  onChange={(e) => setForm((f) => ({ ...f, appPoolName: e.target.value }))}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  placeholder="DefaultAppPool"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm text-slate-400">Port</label>
                <input
                  type="number"
                  min={1}
                  max={65535}
                  value={form.port}
                  onChange={(e) => setForm((f) => ({ ...f, port: parseInt(e.target.value, 10) || 80 }))}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>
            {createStatus && (
              <p
                className={`mt-3 text-sm ${createStatus.type === 'success' ? 'text-emerald-400' : 'text-rose-400'}`}
              >
                {createStatus.msg}
              </p>
            )}
            <button
              type="submit"
              className="mt-4 rounded-lg bg-indigo-600 px-4 py-2 font-medium text-white transition hover:bg-indigo-500"
            >
              Create Site
            </button>
          </form>
        </section>

        {/* Sites List */}
        <section>
          <h2 className="mb-4 text-lg font-semibold text-slate-200">IIS Sites</h2>
          <div className="rounded-xl border border-slate-800 bg-slate-900/50 overflow-hidden">
            {sites.length === 0 ? (
              <div className="p-8 text-center text-slate-400">No sites found or API unavailable.</div>
            ) : (
              <table className="w-full">
                <thead>
                  <tr className="border-b border-slate-700 bg-slate-800/50">
                    <th className="px-4 py-3 text-left text-sm font-medium text-slate-300">Name</th>
                    <th className="px-4 py-3 text-left text-sm font-medium text-slate-300">State</th>
                    <th className="px-4 py-3 text-left text-sm font-medium text-slate-300">Bindings</th>
                    <th className="px-4 py-3 text-left text-sm font-medium text-slate-300">Path</th>
                  </tr>
                </thead>
                <tbody>
                  {sites.map((site) => (
                    <tr key={site.id} className="border-b border-slate-800/50 hover:bg-slate-800/30">
                      <td className="px-4 py-3 text-slate-200">{site.name}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs ${
                            site.state === 'Started' ? 'bg-emerald-900/50 text-emerald-400' : 'bg-slate-700 text-slate-400'
                          }`}
                        >
                          {site.state}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm text-slate-400">{site.bindings?.join(', ') || '-'}</td>
                      <td className="max-w-xs truncate px-4 py-3 text-sm text-slate-400" title={site.physicalPath}>
                        {site.physicalPath || '-'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
