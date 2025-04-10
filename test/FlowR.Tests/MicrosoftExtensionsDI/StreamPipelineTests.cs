﻿using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class StreamPipelineTests
{
    public class OuterBehavior : IStreamPipelineBehavior<StreamPing, Pong>
    {
        private readonly Logger _output;

        public OuterBehavior(Logger output)
        {
            _output = output;
        }

        public async IAsyncEnumerable<Pong> Handle(StreamPing request, StreamHandlerDelegate<Pong> next, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            _output.Messages.Add("Outer before");
            await foreach (var response in TaskAsyncEnumerableExtensions.WithCancellation<Pong>(next(), cancellationToken))
            {
                yield return response;
            }
            _output.Messages.Add("Outer after");
        }
    }

    public class InnerBehavior : IStreamPipelineBehavior<StreamPing, Pong>
    {
        private readonly Logger _output;

        public InnerBehavior(Logger output)
        {
            _output = output;
        }

        public async IAsyncEnumerable<Pong> Handle(StreamPing request, StreamHandlerDelegate<Pong> next, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            _output.Messages.Add("Inner before");
            await foreach (var response in TaskAsyncEnumerableExtensions.WithCancellation<Pong>(next(), cancellationToken))
            {
                yield return response;
            }
            _output.Messages.Add("Inner after");
        }
    }

    [Fact]
    public async Task Should_wrap_with_behavior()
    {
        var output = new Logger();
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(output);
        services.AddTransient<IStreamPipelineBehavior<StreamPing, Pong>, OuterBehavior>();
        services.AddTransient<IStreamPipelineBehavior<StreamPing, Pong>, InnerBehavior>();
        services.AddFlowR(cfg => cfg.RegisterServicesFromAssembly(typeof(Ping).Assembly));
        var provider = services.BuildServiceProvider();

        var mediator = provider.GetRequiredService<IMediator>();

        var stream = mediator.CreateStream(new StreamPing { Message = "Ping" });

        await foreach (var response in stream)
        {
            response.Message.ShouldBe("Ping Pang");
        }

        output.Messages.ShouldBe(new[]
        {
            "Outer before",
            "Inner before",
            "Handler",
            "Inner after",
            "Outer after"
        });
    }
   
    [Fact]
    public async Task Should_register_and_wrap_with_behavior()
    {
        var output = new Logger();
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(output);
        services.AddFlowR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(Ping).Assembly);
            cfg.AddStreamBehavior<IStreamPipelineBehavior<StreamPing, Pong>, OuterBehavior>();
            cfg.AddStreamBehavior<IStreamPipelineBehavior<StreamPing, Pong>, InnerBehavior>();
        });
        var provider = services.BuildServiceProvider();

        var mediator = provider.GetRequiredService<IMediator>();

        var stream = mediator.CreateStream(new StreamPing { Message = "Ping" });

        await foreach (var response in stream)
        {
            response.Message.ShouldBe("Ping Pang");
        }

        output.Messages.ShouldBe(new[]
        {
            "Outer before",
            "Inner before",
            "Handler",
            "Inner after",
            "Outer after"
        });
    }

}