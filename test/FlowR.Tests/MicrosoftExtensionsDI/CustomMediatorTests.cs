using System;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class CustomMediatorTests
{
    private readonly IServiceProvider _provider;

    public CustomMediatorTests()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddFlowR(cfg =>
        {
            cfg.MediatorImplementationType = typeof(MyCustomMediator);
            cfg.RegisterServicesFromAssemblyContaining(typeof(CustomMediatorTests));
        });
        _provider = services.BuildServiceProvider();
    }

    [Fact]
    public void ShouldResolveMediator()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IMediator>());
        ShouldBeTestExtensions.ShouldBe(_provider.GetRequiredService<IMediator>().GetType(), typeof(MyCustomMediator));
    }

    [Fact]
    public void ShouldResolveRequestHandler()
    {
        ShouldBeNullExtensions.ShouldNotBeNull(_provider.GetService<IRequestHandler<Ping, Pong>>());
    }

    [Fact]
    public void ShouldResolveNotificationHandlers()
    {
        _provider.GetServices<INotificationHandler<Pinged>>().Count().ShouldBe(4);
    }

    [Fact]
    public void Can_Call_AddMediatr_multiple_times()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddFlowR(cfg =>
        {
            cfg.MediatorImplementationType = typeof(MyCustomMediator);
            cfg.RegisterServicesFromAssemblyContaining(typeof(CustomMediatorTests));
        });
            
        // Call AddMediatr again, this should NOT override our custom mediatr (With MS DI, last registration wins)
        services.AddFlowR(cfg => cfg.RegisterServicesFromAssemblyContaining(typeof(CustomMediatorTests)));

        var provider = services.BuildServiceProvider();
        var mediator = provider.GetRequiredService<IMediator>();
        ShouldBeTestExtensions.ShouldBe(mediator.GetType(), typeof(MyCustomMediator));
    }
}