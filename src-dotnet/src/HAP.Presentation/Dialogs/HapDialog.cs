using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace HAP.Presentation.Dialogs;

public static class HapDialog
{
    public static MessageBoxResult Show(
        Window? owner,
        string title,
        string message,
        MessageBoxButton buttons = MessageBoxButton.OK,
        bool isDestructive = false,
        string? yesText = null,
        string? noText = null,
        string? cancelText = null)
    {
        var result = MessageBoxResult.None;
        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 22, 0, 0)
        };

        void AddButton(string text, MessageBoxResult buttonResult, bool primary = false, bool cancel = false)
        {
            var button = new Button
            {
                Content = text,
                MinWidth = 104,
                Height = 34,
                Padding = new Thickness(14, 0, 14, 0),
                Margin = new Thickness(8, 0, 0, 0),
                Background = BrushFrom(primary ? isDestructive ? "#B91C1C" : "#0369A1" : "#0F172A"),
                Foreground = BrushFrom("#F8FAFC"),
                BorderBrush = BrushFrom(primary ? isDestructive ? "#EF4444" : "#38BDF8" : "#475569"),
                BorderThickness = new Thickness(1),
                FontWeight = FontWeights.SemiBold,
                IsDefault = primary,
                IsCancel = cancel
            };
            button.Click += (_, _) =>
            {
                result = buttonResult;
                if (Window.GetWindow(button) is { } dialog)
                {
                    dialog.DialogResult = true;
                    dialog.Close();
                }
            };
            buttonPanel.Children.Add(button);
        }

        switch (buttons)
        {
            case MessageBoxButton.OKCancel:
                AddButton(cancelText ?? "Cancel", MessageBoxResult.Cancel, cancel: true);
                AddButton(yesText ?? "OK", MessageBoxResult.OK, primary: true);
                break;
            case MessageBoxButton.YesNo:
                AddButton(noText ?? "No", MessageBoxResult.No, cancel: true);
                AddButton(yesText ?? "Yes", MessageBoxResult.Yes, primary: true);
                break;
            case MessageBoxButton.YesNoCancel:
                AddButton(cancelText ?? "Cancel", MessageBoxResult.Cancel, cancel: true);
                AddButton(noText ?? "No", MessageBoxResult.No);
                AddButton(yesText ?? "Yes", MessageBoxResult.Yes, primary: true);
                break;
            default:
                AddButton(yesText ?? "OK", MessageBoxResult.OK, primary: true);
                break;
        }

        var shell = new Border
        {
            Background = BrushFrom("#111827"),
            BorderBrush = BrushFrom("#334155"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(20),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        Text = title,
                        Foreground = BrushFrom("#F8FAFC"),
                        FontSize = 20,
                        FontWeight = FontWeights.SemiBold,
                        TextWrapping = TextWrapping.Wrap
                    },
                    new Border
                    {
                        Height = 1,
                        Background = BrushFrom("#334155"),
                        Margin = new Thickness(0, 12, 0, 14)
                    },
                    new TextBlock
                    {
                        Text = message,
                        Foreground = BrushFrom("#CBD5E1"),
                        FontSize = 13,
                        TextWrapping = TextWrapping.Wrap,
                        LineHeight = 19
                    },
                    buttonPanel
                }
            }
        };

        var dialog = new Window
        {
            Title = title,
            Width = 460,
            SizeToContent = SizeToContent.Height,
            MinHeight = 190,
            WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
            Owner = owner,
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Content = shell,
            ShowInTaskbar = false
        };

        dialog.ShowDialog();
        return result == MessageBoxResult.None && buttons == MessageBoxButton.OK ? MessageBoxResult.OK : result;
    }

    private static Brush BrushFrom(string color)
    {
        return (Brush)new BrushConverter().ConvertFromString(color)!;
    }
}
