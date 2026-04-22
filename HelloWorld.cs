using System;
using System.Windows.Forms;
using System.Drawing;

public class HelloWorld : Form {
    public HelloWorld() {
        Text = "Kiosk App";
        Size = new Size(300, 200);
        Label lbl = new Label() {
            Text = "Hello World!",
            Location = new Point(100, 80),
            AutoSize = true
        };
        Controls.Add(lbl);
    }

    static void Main() {
        Application.Run(new HelloWorld());
    }
}
