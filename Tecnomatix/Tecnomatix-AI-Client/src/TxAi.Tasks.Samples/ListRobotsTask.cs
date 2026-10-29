using System.Collections.Generic;
using Tecnomatix.Engineering;
using TxAi.Contracts;

namespace TxAi.Tasks.Samples
{
    /// <summary>Read-only sample: lists all robots in the active document.</summary>
    public class ListRobotsTask : ITxAiTask
    {
        public TxAiResult Run(TxAiContext context)
        {
            TxDocument document = TxApplication.ActiveDocument;
            if (document == null)
            {
                return TxAiResult.Fail("No active document.");
            }

            TxObjectList robots = document.PhysicalRoot.GetAllDescendants(new TxTypeFilter(typeof(TxRobot)));
            List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();
            foreach (ITxObject robot in robots)
            {
                if (context.Cancellation.IsCancellationRequested)
                {
                    return TxAiResult.Fail("Cancelled.");
                }

                Dictionary<string, object> item = new Dictionary<string, object>();
                item["name"] = robot.Name;
                item["id"] = robot.Id;
                items.Add(item);
            }

            context.Log("Found " + items.Count + " robot(s).");
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["count"] = items.Count;
            data["robots"] = items;
            return TxAiResult.Success(data, "Listed " + items.Count + " robot(s).");
        }
    }
}
