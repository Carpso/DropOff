using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;

class Program
{
    static async Task Main(string[] args)
    {
        if (args.Length == 0) { Console.WriteLine("usage: ocr <image>"); return; }
        var file = await StorageFile.GetFileFromPathAsync(args[0]);
        var stream = await file.OpenAsync(FileAccessMode.Read);
        var decoder = await BitmapDecoder.CreateAsync(stream);
        var bitmap = await decoder.GetSoftwareBitmapAsync();
        var engine = OcrEngine.TryCreateFromUserProfileLanguages();
        if (engine == null) { Console.WriteLine("NO OCR ENGINE"); return; }
        var result = await engine.RecognizeAsync(bitmap);
        Console.WriteLine("===== TEXT =====");
        Console.WriteLine(result.Text);
        Console.WriteLine("===== LINES =====");
        foreach (var line in result.Lines)
            Console.WriteLine(line.Text);
    }
}
