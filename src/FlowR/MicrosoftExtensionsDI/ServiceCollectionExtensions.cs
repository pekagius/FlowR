using System;
using System.Linq;
using FlowR;
using FlowR.Registration;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Microsoft.Extensions.DependencyInjection;

/// <summary>
/// Extension methods for adding FlowR services to the specified <see cref="IServiceCollection" />.
/// </summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Adds FlowR services to the specified <see cref="IServiceCollection" />.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection" /> to add services to.</param>
    /// <param name="configuration">The action used to configure FlowR.</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    /// <remarks>
    /// After calling AddFlowR, you can resolve an <see cref="IMediator"/> instance using the container.
    /// </remarks>
    public static IServiceCollection AddFlowR(this IServiceCollection services, Action<FlowRServiceConfiguration> configuration)
    {
        var serviceConfig = new FlowRServiceConfiguration();

        configuration(serviceConfig);

        return services.AddFlowR(serviceConfig);
    }
    
    /// <summary>
    /// Adds FlowR services to the specified <see cref="IServiceCollection" />.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection" /> to add services to.</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    /// <remarks>
    /// After calling AddFlowR, you can resolve an <see cref="IMediator"/> instance using the container.
    /// </remarks>
    public static IServiceCollection AddFlowR(this IServiceCollection services)
    {
        var serviceConfig = new FlowRServiceConfiguration();
        serviceConfig.RegisterServicesFromAssembly(typeof(IMediator).Assembly);
        
        return services.AddFlowR(serviceConfig);
    }
    
    /// <summary>
    /// Adds FlowR services to the specified <see cref="IServiceCollection" />.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection" /> to add services to.</param>
    /// <param name="configuration">Configuration options</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    /// <remarks>
    /// After calling AddFlowR, you can resolve an <see cref="IMediator"/> instance using the container.
    /// </remarks>
    public static IServiceCollection AddFlowR(this IServiceCollection services, 
        FlowRServiceConfiguration configuration)
    {
        if (!configuration.AssembliesToRegister.Any())
        {
            throw new ArgumentException("No assemblies found to scan. Please add at least one assembly to scan for handlers.");
        }

        ServiceRegistrar.SetGenericRequestHandlerRegistrationLimitations(configuration);

        ServiceRegistrar.AddFlowRClassesWithTimeout(services, configuration);

        ServiceRegistrar.AddRequiredServices(services, configuration);

        return services;
    }
    
    /// <summary>
    /// Adds MediatR services to the specified <see cref="IServiceCollection" />.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection" /> to add services to.</param>
    /// <param name="configuration">The action used to configure MediatR.</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    /// <remarks>
    /// Compatibility method for MediatR
    /// </remarks>
    [Obsolete("Use AddFlowR instead")]
    public static IServiceCollection AddMediatR(this IServiceCollection services, Action<FlowRServiceConfiguration> configuration)
    {
        return AddFlowR(services, configuration);
    }
    
    /// <summary>
    /// Adds MediatR services to the specified <see cref="IServiceCollection" />.
    /// </summary>
    /// <param name="services">The <see cref="IServiceCollection" /> to add services to.</param>
    /// <returns>The <see cref="IServiceCollection"/> so that additional calls can be chained.</returns>
    /// <remarks>
    /// Compatibility method for MediatR
    /// </remarks>
    [Obsolete("Use AddFlowR instead")]
    public static IServiceCollection AddMediatR(this IServiceCollection services)
    {
        return AddFlowR(services);
    }
}