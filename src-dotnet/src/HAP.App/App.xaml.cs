namespace HAP.App;

public partial class App : System.Windows.Application
{
    private void OnStartup(object sender, System.Windows.StartupEventArgs e)
    {
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }
}
