using System.IO;

namespace Elta.Core.Tests
{
    /// <summary>检测运行目录属于「完整仓库」还是「仅 windows/ 的独立存档」（验收导出包）。</summary>
    internal sealed record ReleaseLayoutResult(bool RepoRootFound, string? RepoRoot, bool ArchiveLayout, string? WindowsRoot);

    internal static class ReleaseLayout
    {
        public static ReleaseLayoutResult Detect(string startDir)
        {
            string? windowsRoot = null;
            DirectoryInfo? dir = new DirectoryInfo(startDir);
            while (dir != null)
            {
                if (File.Exists(Path.Combine(dir.FullName, "windows", "src", "Elta.Core", "Elta.Core.csproj")))
                {
                    windowsRoot ??= dir.FullName;
                    if (File.Exists(Path.Combine(dir.FullName, "Resources", "Info.plist")))
                    {
                        return new ReleaseLayoutResult(true, dir.FullName, false, dir.FullName);
                    }
                }
                dir = dir.Parent;
            }
            return new ReleaseLayoutResult(false, null, windowsRoot != null, windowsRoot);
        }
    }
}
