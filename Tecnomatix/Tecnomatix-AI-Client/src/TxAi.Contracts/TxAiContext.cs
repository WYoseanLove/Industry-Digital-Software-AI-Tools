using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;

namespace TxAi.Contracts
{
    public sealed class TxAiContext
    {
        private readonly Action<string> _log;

        public TxAiContext(IDictionary<string, object> args, CancellationToken cancellation, Action<string> log)
        {
            Args = args ?? new Dictionary<string, object>();
            Cancellation = cancellation;
            _log = log;
        }

        public IDictionary<string, object> Args { get; private set; }

        /// <summary>Signalled on timeout or an explicit cancel request; long loops must poll it.</summary>
        public CancellationToken Cancellation { get; private set; }

        public void Log(string message)
        {
            if (_log != null)
            {
                _log(message);
            }
        }

        public string GetString(string name, string defaultValue)
        {
            object value;
            if (Args.TryGetValue(name, out value) && value != null)
            {
                return Convert.ToString(value, CultureInfo.InvariantCulture);
            }
            return defaultValue;
        }

        public int GetInt(string name, int defaultValue)
        {
            object value;
            if (Args.TryGetValue(name, out value) && value != null)
            {
                try
                {
                    return Convert.ToInt32(value, CultureInfo.InvariantCulture);
                }
                catch (FormatException)
                {
                }
                catch (InvalidCastException)
                {
                }
                catch (OverflowException)
                {
                }
            }
            return defaultValue;
        }
    }
}
