using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Threading.Tasks;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class SettingsManagerThreadSafetyTests
    {
        private static SettingsManager NewManager(out InMemorySecretStore secrets)
        {
            var store = new InMemorySettingsStore();
            secrets = new InMemorySecretStore();
            return new SettingsManager(store, secrets, SettingsDefaults.MacParity);
        }

        [Fact]
        public async Task ConcurrentReads_DoNotCrash()
        {
            SettingsManager sm = NewManager(out _);
            Task[] tasks = Enumerable.Range(0, 10).Select(i => Task.Run(() =>
            {
                _ = sm.ApiProvider;
                _ = sm.ActiveApiKey;
                _ = sm.HotkeyKeyCode;
                _ = sm.HotkeyModifiers;
            })).ToArray();
            await Task.WhenAll(tasks);
        }

        [Fact]
        public async Task ConcurrentApiProviderGetSet_IsConsistent()
        {
            SettingsManager sm = NewManager(out _);
            sm.ApiProvider = AIProvider.Deepseek;

            var readValues = new ConcurrentBag<AIProvider>();
            Task[] tasks = Enumerable.Range(0, 50).Select(i => Task.Run(() =>
            {
                readValues.Add(sm.ApiProvider);
            })).ToArray();
            await Task.WhenAll(tasks);

            Assert.True(readValues.All(v => v == AIProvider.Deepseek), "All reads should see consistent value");
        }

        [Fact]
        public async Task ConcurrentHotkeyReads_AreConsistent()
        {
            SettingsManager sm = NewManager(out _);
            sm.HotkeyKeyCode = 0x03;

            var readValues = new ConcurrentBag<int>();
            Task[] tasks = Enumerable.Range(0, 20).Select(i => Task.Run(() =>
            {
                readValues.Add(sm.HotkeyKeyCode);
            })).ToArray();
            await Task.WhenAll(tasks);

            Assert.True(readValues.All(v => v == 0x03), "All concurrent reads should return same value");
        }

        [Fact]
        public async Task ActiveApiKey_IsConsistentDuringConcurrentAccess()
        {
            SettingsManager sm = NewManager(out _);
            sm.ApiProvider = AIProvider.Deepseek;
            sm.SetApiKey("concurrency-test-key", AIProvider.Deepseek);

            Task[] tasks = Enumerable.Range(0, 20).Select(i => Task.Run(() =>
            {
                _ = sm.ActiveApiKey;
            })).ToArray();
            await Task.WhenAll(tasks);

            Assert.Equal("concurrency-test-key", sm.ActiveApiKey);
        }
    }
}
