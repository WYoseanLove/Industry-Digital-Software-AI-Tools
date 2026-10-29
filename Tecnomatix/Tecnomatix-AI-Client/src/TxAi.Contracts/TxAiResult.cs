namespace TxAi.Contracts
{
    public sealed class TxAiResult
    {
        private TxAiResult()
        {
        }

        public bool Ok { get; private set; }

        public string Message { get; private set; }

        /// <summary>JSON-serializable payload: primitives, lists and string-keyed dictionaries.</summary>
        public object Data { get; private set; }

        public static TxAiResult Success(object data, string message)
        {
            return new TxAiResult { Ok = true, Data = data, Message = message };
        }

        public static TxAiResult Fail(string message)
        {
            return new TxAiResult { Ok = false, Message = message };
        }
    }
}
