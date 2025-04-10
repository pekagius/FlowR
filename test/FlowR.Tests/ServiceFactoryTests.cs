using System;
using System.Collections;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FlowR.Tests;

public class ServiceFactoryTests
{
    public class Ping : IRequest<Pong>
    {

    }

    public class Pong
    {
        public string? Message { get; set; }
    }

    [Fact]
    public async Task Should_throw_given_no_handler()
    {
        var serviceCollection = new ServiceCollection();
        var serviceProvider = serviceCollection.BuildServiceProvider();

        var mediator = new Mediator(serviceProvider, new FlowR.NotificationPublishers.TaskWhenAllPublisher());

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => mediator.Send(new Ping())
        );
    }
}