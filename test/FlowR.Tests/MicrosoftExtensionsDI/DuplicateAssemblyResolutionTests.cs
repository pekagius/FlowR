using System;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace FlowR.Tests.MicrosoftExtensionsDI;

public class DuplicateAssemblyResolutionTests
{
    private readonly IServiceProvider _provider;

    public DuplicateAssemblyResolutionTests()
    {
        IServiceCollection services = new ServiceCollection();
        services.AddSingleton(new Logger());
        services.AddFlowR(cfg => cfg.RegisterServicesFromAssemblies(typeof(Ping).Assembly, typeof(Ping).Assembly));
        _provider = services.BuildServiceProvider();
    }

    [Fact]
    public void ShouldResolveNotificationHandlersOnlyOnce()
    {
        _provider.GetServices<INotificationHandler<Pinged>>().Count().ShouldBe(4);
    }
}