using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace XiaoXiaoXin;

public sealed class MainForm : Form
{
    private const int HotkeyId = 0x5858;
    private const int WmHotkey = 0x0312;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private readonly WebView2 web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Transparent };
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private readonly NotifyIcon tray = new();
    private CancellationTokenSource? refreshCancellation;
    private readonly Dictionary<string, (DateTime Time, TrendData Data)> trendCache = new();
    private bool compact = true;
    private Point dragCursor;
    private Point dragWindow;

    public MainForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        TopMost = true;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(120, 56);
        BackColor = Color.Lime;
        TransparencyKey = Color.Lime;
        Controls.Add(web);

        var handle = new Label {
            Text = "⠿", ForeColor = Color.FromArgb(110, 80, 80, 80), BackColor = Color.Transparent,
            Location = new Point(2, 1), Size = new Size(24, 22), Font = new Font("Segoe UI", 10)
        };
        handle.MouseDown += (_, e) => { if (e.Button == MouseButtons.Left) { dragCursor = Cursor.Position; dragWindow = Location; } };
        handle.MouseMove += (_, e) => { if (e.Button == MouseButtons.Left) Location = new Point(dragWindow.X + Cursor.Position.X - dragCursor.X, dragWindow.Y + Cursor.Position.Y - dragCursor.Y); };
        Controls.Add(handle);
        handle.BringToFront();

        tray.Text = "小小信";
        tray.Icon = SystemIcons.Application;
        tray.Visible = true;
        var menu = new ContextMenuStrip();
        menu.Items.Add("显示 / 隐藏", null, (_, _) => ToggleVisibility());
        menu.Items.Add("退出小小信", null, (_, _) => Close());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ToggleVisibility();

        Shown += async (_, _) => await InitializeWebAsync();
        FormClosed += (_, _) => { tray.Visible = false; UnregisterHotKey(Handle, HotkeyId); };
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RegisterHotKey(Handle, HotkeyId, ModControl | ModShift, (uint)Keys.H);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && m.WParam.ToInt32() == HotkeyId) ToggleVisibility();
        base.WndProc(ref m);
    }

    private async Task InitializeWebAsync()
    {
        await web.EnsureCoreWebView2Async();
        web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        web.CoreWebView2.Settings.IsZoomControlEnabled = false;
        web.CoreWebView2.WebMessageReceived += WebMessageReceived;
        web.Source = new Uri(Path.Combine(AppContext.BaseDirectory, "Web", "index.html"));
    }

    private async void WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var document = JsonDocument.Parse(e.WebMessageAsJson);
        var root = document.RootElement;
        if (root.ValueKind == JsonValueKind.String) {
            switch (root.GetString()) {
                case "collapse": SetCompact(true); break;
                case "expand": SetCompact(false); break;
                case "boss": ToggleVisibility(); break;
            }
            return;
        }
        if (!root.TryGetProperty("type", out var type)) return;
        if (type.GetString() == "quote" && root.TryGetProperty("code", out var code)) await LoadQuoteAsync(code.GetString() ?? "");
        if (type.GetString() == "search" && root.TryGetProperty("query", out var query)) await SearchAsync(query.GetString() ?? "");
    }

    private void SetCompact(bool value)
    {
        if (compact == value) return;
        var topRight = new Point(Right, Top);
        compact = value;
        ClientSize = value ? new Size(120, 56) : new Size(200, 200);
        Location = new Point(topRight.X - Width, topRight.Y);
    }

    private void ToggleVisibility() { if (Visible) Hide(); else { Show(); Activate(); } }

    private async Task LoadQuoteAsync(string rawCode)
    {
        var code = new string(rawCode.Where(char.IsDigit).Take(6).ToArray());
        if (code.Length != 6) { await SendErrorAsync("请输入六位股票代码～"); return; }
        refreshCancellation?.Cancel();
        refreshCancellation = new CancellationTokenSource();
        var token = refreshCancellation.Token;
        try {
            var (quote, source) = await FetchQuoteWithFallbackAsync(code, token);
            TrendData trend;
            if (trendCache.TryGetValue(code, out var cached) && DateTime.UtcNow - cached.Time < TimeSpan.FromMinutes(5)) trend = cached.Data;
            else {
                trend = await TryFetchTrendAsync(code, token) ?? new TrendData();
                if (trend.Points.Count > 0) trendCache[code] = (DateTime.UtcNow, trend);
            }
            var payload = new { name = quote.Name, displayCode = $"{code}.{(code.StartsWith('6') ? "SH" : "SZ")}", price = quote.Price, open = quote.Open, high = quote.High, low = quote.Low, previousClose = quote.PreviousClose, points = trend.Points, source };
            await ExecuteAsync($"window.applyMarketData({JsonSerializer.Serialize(payload)})");
        } catch (OperationCanceledException) { }
        catch { await SendErrorAsync("主数据源和备用源都没有回应，请稍后重试。"); }
    }

    private async Task<(MarketQuote Quote, string Source)> FetchQuoteWithFallbackAsync(string code, CancellationToken token)
    {
        try { return (await FetchEastmoneyAsync(code, token), "东财"); }
        catch { return (await FetchTencentAsync(code, token), "腾讯备用源"); }
    }

    private async Task<MarketQuote> FetchEastmoneyAsync(string code, CancellationToken token)
    {
        var secid = $"{(code.StartsWith('6') ? "1" : "0")}.{code}";
        var url = $"https://push2.eastmoney.com/api/qt/stock/get?secid={secid}&fields=f43,f44,f45,f46,f58,f60";
        using var json = JsonDocument.Parse(await GetWithRetryAsync(url, "https://quote.eastmoney.com/", token));
        var d = json.RootElement.GetProperty("data");
        double P(string key) => d.TryGetProperty(key, out var v) && v.TryGetDouble(out var n) ? n / 100d : 0;
        var quote = new MarketQuote(d.GetProperty("f58").GetString() ?? code, P("f43"), P("f46"), P("f44"), P("f45"), P("f60"));
        if (quote.Price <= 0) throw new InvalidDataException();
        return quote;
    }

    private async Task<MarketQuote> FetchTencentAsync(string code, CancellationToken token)
    {
        var symbol = $"{(code.StartsWith('6') ? "sh" : "sz")}{code}";
        var data = await GetWithRetryAsync($"https://qt.gtimg.cn/q={symbol}", "https://gu.qq.com/", token);
        var text = Encoding.GetEncoding("GB18030").GetString(data);
        var start = text.IndexOf('"') + 1; var end = text.LastIndexOf('"');
        if (start <= 0 || end <= start) throw new InvalidDataException();
        var v = text[start..end].Split('~');
        if (v.Length <= 34) throw new InvalidDataException();
        return new MarketQuote(v[1], double.Parse(v[3]), double.Parse(v[5]), double.Parse(v[33]), double.Parse(v[34]), double.Parse(v[4]));
    }

    private async Task<TrendData?> TryFetchTrendAsync(string code, CancellationToken token)
    {
        try {
            var secid = $"{(code.StartsWith('6') ? "1" : "0")}.{code}";
            var url = $"https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid={secid}&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11&fields2=f51,f52,f53,f54,f55,f56,f57,f58&ndays=1&iscr=0";
            using var json = JsonDocument.Parse(await GetWithRetryAsync(url, "https://quote.eastmoney.com/", token));
            var result = new TrendData();
            foreach (var row in json.RootElement.GetProperty("data").GetProperty("trends").EnumerateArray()) {
                var fields = (row.GetString() ?? "").Split(',');
                if (fields.Length > 2 && double.TryParse(fields[2], out var value)) result.Points.Add(value);
            }
            return result;
        } catch { return null; }
    }

    private async Task SearchAsync(string query)
    {
        try {
            var url = $"https://searchapi.eastmoney.com/api/suggest/get?input={Uri.EscapeDataString(query)}&type=14&token=D43BF722C8E33BDC906FB84D85E326E8";
            using var json = JsonDocument.Parse(await GetWithRetryAsync(url, "https://quote.eastmoney.com/", CancellationToken.None));
            var results = json.RootElement.GetProperty("QuotationCodeTable").GetProperty("Data").EnumerateArray().Take(6).Select(item => {
                var code = item.GetProperty("Code").GetString() ?? "";
                return new { code, name = item.GetProperty("Name").GetString() ?? code, displayCode = $"{code}.{(code.StartsWith('6') ? "SH" : "SZ")}" };
            }).ToArray();
            await ExecuteAsync($"window.applySearchResults({JsonSerializer.Serialize(results)})");
        } catch { await ExecuteAsync("window.applySearchResults([])"); }
    }

    private async Task<byte[]> GetWithRetryAsync(string url, string referer, CancellationToken token)
    {
        Exception? last = null;
        foreach (var delay in new[] { 0, 1000, 3000 }) {
            try {
                if (delay > 0) await Task.Delay(delay, token);
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
                request.Headers.Referrer = new Uri(referer);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
                response.EnsureSuccessStatusCode();
                return await response.Content.ReadAsByteArrayAsync(token);
            } catch (Exception ex) when (ex is not OperationCanceledException) { last = ex; }
        }
        throw last ?? new HttpRequestException();
    }

    private Task SendErrorAsync(string message) => ExecuteAsync($"window.applyMarketError({JsonSerializer.Serialize(message)})");
    private async Task ExecuteAsync(string script) { if (web.CoreWebView2 is not null) await web.CoreWebView2.ExecuteScriptAsync(script); }

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private sealed record MarketQuote(string Name, double Price, double Open, double High, double Low, double PreviousClose);
    private sealed class TrendData { public List<double> Points { get; } = []; }
}
