using System;
using System.Threading;
using System.Windows.Forms;

namespace TxAi.Addin
{
    /// <summary>Marshals work onto the Process Simulate UI thread. Must be created on that thread.</summary>
    public sealed class UiThreadDispatcher : IDisposable
    {
        private readonly Control _control;

        public UiThreadDispatcher()
        {
            _control = new Control();
            // Forces handle creation on the current (UI) thread.
            IntPtr unused = _control.Handle;
        }

        /// <summary>
        /// Runs the function on the UI thread and waits up to timeoutMs.
        /// Returns false on timeout; the work may still be running or queued.
        /// </summary>
        public bool TryInvoke<T>(Func<T> work, int timeoutMs, out T result, out Exception error)
        {
            T localResult = default(T);
            Exception localError = null;
            ManualResetEventSlim done = new ManualResetEventSlim(false);

            _control.BeginInvoke(new MethodInvoker(delegate
            {
                try
                {
                    localResult = work();
                }
                catch (Exception ex)
                {
                    localError = ex;
                }
                finally
                {
                    done.Set();
                }
            }));

            if (!done.Wait(timeoutMs))
            {
                result = default(T);
                error = null;
                return false;
            }

            result = localResult;
            error = localError;
            return true;
        }

        public void Dispose()
        {
            _control.Dispose();
        }
    }
}
