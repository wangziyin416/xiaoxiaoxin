using System.Text;

namespace XiaoXiaoXin;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
