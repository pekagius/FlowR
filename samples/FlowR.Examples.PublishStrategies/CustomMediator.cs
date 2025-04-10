using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace FlowR.Examples.PublishStrategies;

public class CustomPublisher : INotificationPublisher
{
    private readonly Func<IEnumerable<NotificationHandlerExecutor>, INotification, CancellationToken, Task> _publishStrategy;

    public CustomPublisher(Func<IEnumerable<NotificationHandlerExecutor>, INotification, CancellationToken, Task> publishStrategy)
    {
        _publishStrategy = publishStrategy;
    }

    public Task Publish(IEnumerable<NotificationHandlerExecutor> handlers, INotification notification, CancellationToken cancellationToken)
    {
        return _publishStrategy(handlers, notification, cancellationToken);
    }
}

public class CustomMediator : Mediator
{
    public CustomMediator(IServiceProvider serviceFactory, Func<IEnumerable<NotificationHandlerExecutor>, INotification, CancellationToken, Task> publish) 
        : base(serviceFactory, new CustomPublisher(publish))
    {
    }
}