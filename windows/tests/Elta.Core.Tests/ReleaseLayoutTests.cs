using System;
using System.IO;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class ReleaseLayoutTests
    {
        private static string MakeFixture(string name, bool withResources, bool withWindowsSrc)
        {
            string root = Path.Combine(Path.GetTempPath(), "elta-layout-" + name + "-" + Guid.NewGuid().ToString("N"));
            if (withWindowsSrc)
            {
                string src = Path.Combine(root, "windows", "src", "Elta.Core");
                Directory.CreateDirectory(src);
                File.WriteAllText(Path.Combine(src, "Elta.Core.csproj"), "<Project/>");
            }
            if (withResources)
            {
                string res = Path.Combine(root, "Resources");
                Directory.CreateDirectory(res);
                File.WriteAllText(Path.Combine(res, "Info.plist"), "<plist/>");
            }
            return root;
        }

        [Fact]
        public void Detect_FromDeepInsideRepo_FindsRepoRoot()
        {
            string root = MakeFixture("repo", withResources: true, withWindowsSrc: true);
            try
            {
                string start = Path.Combine(root, "windows", "tests", "Elta.Core.Tests", "bin", "Debug", "net8.0");
                Directory.CreateDirectory(start);
                ReleaseLayoutResult r = ReleaseLayout.Detect(start);
                Assert.True(r.RepoRootFound);
                Assert.Equal(root, r.RepoRoot);
                Assert.False(r.ArchiveLayout);
            }
            finally { Directory.Delete(root, recursive: true); }
        }

        [Fact]
        public void Detect_WindowsArchiveWithoutResources_IsArchive()
        {
            string root = MakeFixture("archive", withResources: false, withWindowsSrc: true);
            try
            {
                string start = Path.Combine(root, "windows", "tests", "Elta.Core.Tests", "bin", "Debug", "net8.0");
                Directory.CreateDirectory(start);
                ReleaseLayoutResult r = ReleaseLayout.Detect(start);
                Assert.False(r.RepoRootFound);
                Assert.Null(r.RepoRoot);
                Assert.True(r.ArchiveLayout);
                Assert.Equal(root, r.WindowsRoot);
            }
            finally { Directory.Delete(root, recursive: true); }
        }

        [Fact]
        public void Detect_Nothing_FindsNothing()
        {
            string root = Path.Combine(Path.GetTempPath(), "elta-layout-empty-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                string start = Path.Combine(root, "some", "where");
                Directory.CreateDirectory(start);
                ReleaseLayoutResult r = ReleaseLayout.Detect(start);
                Assert.False(r.RepoRootFound);
                Assert.False(r.ArchiveLayout);
                Assert.Null(r.RepoRoot);
                Assert.Null(r.WindowsRoot);
            }
            finally { Directory.Delete(root, recursive: true); }
        }
    }
}
