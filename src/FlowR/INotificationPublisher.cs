using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace FlowR;

public interface INotificationPublisher
{
    Task Publish(IEnumerable<NotificationHandlerExecutor> handlerExecutors, INotification notification,
        CancellationToken cancellationToken);
}