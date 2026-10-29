namespace TxAi.Contracts
{
    /// <summary>Entry point of a task DLL. Always invoked on the Process Simulate UI thread.</summary>
    public interface ITxAiTask
    {
        TxAiResult Run(TxAiContext context);
    }
}
