using System.Threading;
using System.Threading.Tasks;

namespace FlowR.Benchmarks
{
    public class Pinged : INotification
    {
    }

    public class PingedHandler : INotificationHandler<Pinged>
    {
        public Task Handle(Pinged notification, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }
}