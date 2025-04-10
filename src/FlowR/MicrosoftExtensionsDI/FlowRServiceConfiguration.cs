using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using FlowR.Entities;
using FlowR.MicrosoftExtensionsDI;
using FlowR.NotificationPublishers;
using FlowR.Pipeline;
using FlowR.Registration;
using Microsoft.Extensions.DependencyInjection;

namespace FlowR;

/// <summary>
/// Configuration for FlowR services
/// </summary>
public class FlowRServiceConfiguration
{
    /// <summary>
    /// Optional filter for types to register. Default is a function that returns true.
    /// </summary>
    public Func<Type, bool> TypeFilter { get; set; } = _ => true;
    
    /// <summary>
    /// Mediator implementation type to register. Default is <see cref="Mediator"/>
    /// </summary>
    public Type MediatorImplementationType { get; set; } = typeof(Mediator);

    /// <summary>
    /// Strategy for publishing notifications. Default is <see cref="ForeachAwaitPublisher"/>
    /// </summary>
    public INotificationPublisher? NotificationPublisher { get; set; }

    /// <summary>
    /// Type of notification publishing strategy to register. If set, this overrides <see cref="NotificationPublisher"/>
    /// </summary>
    public Type? NotificationPublisherType { get; set; }

    /// <summary>
    /// Service lifetime for registering services. Default is <see cref="ServiceLifetime.Transient"/>
    /// </summary>
    public ServiceLifetime Lifetime { get; set; } = ServiceLifetime.Transient;

    /// <summary>
    /// Skips FlowR core registration. Default is false.
    /// </summary>
    public bool SkipFlowRCoreDependencies { get; set; }

    /// <summary>
    /// Request Exception Action Processor strategy. Default is <see cref="RequestExceptionActionProcessorStrategy.ApplyForUnhandledExceptions"/>
    /// </summary>
    public RequestExceptionActionProcessorStrategy RequestExceptionActionProcessorStrategy { get; set; }
        = RequestExceptionActionProcessorStrategy.ApplyForUnhandledExceptions;

    /// <summary>
    /// Assemblies to scan. Default is no assemblies.
    /// </summary>
    public IList<Assembly> AssembliesToRegister { get; } = new List<Assembly>();

    /// <summary>
    /// List of behaviors to register in specific order
    /// </summary>
    public List<ServiceDescriptor> BehaviorsToRegister { get; } = new();

    /// <summary>
    /// List of stream behaviors to register in specific order
    /// </summary>
    public List<ServiceDescriptor> StreamBehaviorsToRegister { get; } = new();

    /// <summary>
    /// List of request pre-processors to register in specific order
    /// </summary>
    public List<ServiceDescriptor> RequestPreProcessorsToRegister { get; } = new();

    /// <summary>
    /// List of request post-processors to register in specific order
    /// </summary>
    public List<ServiceDescriptor> RequestPostProcessorsToRegister { get; } = new();

    /// <summary>
    /// Automatically register processors during assembly scanning
    /// </summary>
    public bool AutoRegisterProcessors { get; set; } = true;
    
    /// <summary>
    /// Configure the maximum number of type parameters a generic request handler can have. To disable this limitation, set the value to 0.
    /// </summary>
    public int MaxOpenGenericRequestParamCount { get; set; } = 100;
    
    /// <summary>
    /// Configure the maximum number of types a generic request type parameter constraint can close over. To disable this limitation, set the value to 0.
    /// </summary>
    public int MaxOpenGenericRequestTypeCount { get; set; } = 100;
    
    /// <summary>
    /// Configure the maximum number of generic request handler types FlowR tries to register. To disable this limitation, set the value to 0.
    /// </summary>
    public int MaxOpenGenericHandlerCount { get; set; } = 10000;
    
    /// <summary>
    /// Configure the timeout in milliseconds after which the generic handler registration process is terminated with an error. To disable this limitation, set the value to 0.
    /// </summary>
    public int GenericRegistrationTimeout { get; set; } = 3000;

    /// <summary>
    /// Flag controlling whether FlowR tries to register handlers that contain generic type parameters.
    /// </summary>
    public bool RegisterGenericHandlers { get; set; } = false;

    /// <summary>
    /// Register an assembly to scan
    /// </summary>
    /// <param name="assembly">Assembly to scan</param>
    /// <returns>The configuration for chaining</returns>
    public FlowRServiceConfiguration RegisterServicesFromAssembly(Assembly assembly)
    {
        AssembliesToRegister.Add(assembly);
        return this;
    }

    /// <summary>
    /// Register all assemblies to scan
    /// </summary>
    /// <param name="assemblies">Assemblies to scan</param>
    /// <returns>The configuration for chaining</returns>
    public FlowRServiceConfiguration RegisterServicesFromAssemblies(params Assembly[] assemblies)
    {
        foreach (var assembly in assemblies)
        {
            RegisterServicesFromAssembly(assembly);
        }
        return this;
    }

    /// <summary>
    /// Register an assembly containing the specified type for scanning
    /// </summary>
    /// <typeparam name="T">Type from the assembly to scan</typeparam>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration RegisterServicesFromAssemblyContaining<T>()
        => RegisterServicesFromAssemblyContaining(typeof(T));

    /// <summary>
    /// Register an assembly containing the specified type for scanning
    /// </summary>
    /// <param name="type">Type from the assembly to scan</param>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration RegisterServicesFromAssemblyContaining(Type type)
        => RegisterServicesFromAssembly(type.Assembly);

    /// <summary>
    /// Register a closed behavior type
    /// </summary>
    /// <typeparam name="TServiceType">Closed behavior interface type</typeparam>
    /// <typeparam name="TImplementationType">Closed behavior implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration AddBehavior<TServiceType, TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddBehavior(typeof(TServiceType), typeof(TImplementationType), serviceLifetime);

    /// <summary>
    /// Register a closed behavior type for all <see cref="IPipelineBehavior{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <typeparam name="TImplementationType">Closed behavior implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration AddBehavior<TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        return AddBehavior(typeof(TImplementationType), serviceLifetime);
    }

    /// <summary>
    /// Register a closed behavior type for all <see cref="IPipelineBehavior{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <param name="implementationType">Closed behavior implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration AddBehavior(Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        var implementedGenericInterfaces = implementationType.FindInterfacesThatClose(typeof(IPipelineBehavior<,>)).ToList();

        if (implementedGenericInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{implementationType.Name} must implement {typeof(IPipelineBehavior<,>).FullName}");
        }

        foreach (var implementedBehaviorType in implementedGenericInterfaces)
        {
            BehaviorsToRegister.Add(new ServiceDescriptor(implementedBehaviorType, implementationType, serviceLifetime));
        }

        return this;
    }

    /// <summary>
    /// Register a closed behavior type
    /// </summary>
    /// <param name="serviceType">Closed behavior interface type</param>
    /// <param name="implementationType">Closed behavior implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This configuration</returns>
    public FlowRServiceConfiguration AddBehavior(Type serviceType, Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        BehaviorsToRegister.Add(new ServiceDescriptor(serviceType, implementationType, serviceLifetime));

        return this;
    }

    /// <summary>
    /// Registers an open behavior type against the <see cref="IPipelineBehavior{TRequest,TResponse}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviorType">An open generic behavior type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenBehavior(Type openBehaviorType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        if (!openBehaviorType.IsGenericType)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must be generic");
        }

        var implementedGenericInterfaces = openBehaviorType.GetInterfaces().Where(i => i.IsGenericType).Select(i => i.GetGenericTypeDefinition());
        var implementedOpenBehaviorInterfaces = new HashSet<Type>(implementedGenericInterfaces.Where(i => i == typeof(IPipelineBehavior<,>)));

        if (implementedOpenBehaviorInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must implement {typeof(IPipelineBehavior<,>).FullName}");
        }

        foreach (var openBehaviorInterface in implementedOpenBehaviorInterfaces)
        {
            BehaviorsToRegister.Add(new ServiceDescriptor(openBehaviorInterface, openBehaviorType, serviceLifetime));
        }

        return this;
    }

    /// <summary>
    /// Registers multiple open behavior types against the <see cref="IPipelineBehavior{TRequest,TResponse}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviorTypes">An open generic behavior type list includes multiple open generic behavior types.</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenBehaviors(IEnumerable<Type> openBehaviorTypes, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        foreach (var openBehaviorType in openBehaviorTypes)
        {
            AddOpenBehavior(openBehaviorType, serviceLifetime);
        }

        return this;
    }

    /// <summary>
    /// Registers open behaviors against the <see cref="IPipelineBehavior{TRequest,TResponse}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviors">An open generic behavior list includes multiple <see cref="OpenBehavior"/> open generic behaviors.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenBehaviors(IEnumerable<OpenBehavior> openBehaviors)
    {
        foreach (var openBehavior in openBehaviors)
        {
            AddOpenBehavior(openBehavior.OpenBehaviorType!, openBehavior.ServiceLifetime);
        }

        return this;
    }
    
    /// <summary>
    /// Register a closed stream behavior type
    /// </summary>
    /// <typeparam name="TServiceType">Closed stream behavior interface type</typeparam>
    /// <typeparam name="TImplementationType">Closed stream behavior implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddStreamBehavior<TServiceType, TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddStreamBehavior(typeof(TServiceType), typeof(TImplementationType), serviceLifetime);
    
    /// <summary>
    /// Register a closed stream behavior type
    /// </summary>
    /// <param name="serviceType">Closed stream behavior interface type</param>
    /// <param name="implementationType">Closed stream behavior implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddStreamBehavior(Type serviceType, Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        StreamBehaviorsToRegister.Add(new ServiceDescriptor(serviceType, implementationType, serviceLifetime));

        return this;
    }
    
    /// <summary>
    /// Register a closed stream behavior type against all <see cref="IStreamPipelineBehavior{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <typeparam name="TImplementationType">Closed stream behavior implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddStreamBehavior<TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddStreamBehavior(typeof(TImplementationType), serviceLifetime);
    
    /// <summary>
    /// Register a closed stream behavior type against all <see cref="IStreamPipelineBehavior{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <param name="implementationType">Closed stream behavior implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddStreamBehavior(Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        var implementedGenericInterfaces = implementationType.FindInterfacesThatClose(typeof(IStreamPipelineBehavior<,>)).ToList();

        if (implementedGenericInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{implementationType.Name} must implement {typeof(IStreamPipelineBehavior<,>).FullName}");
        }

        foreach (var implementedBehaviorType in implementedGenericInterfaces)
        {
            StreamBehaviorsToRegister.Add(new ServiceDescriptor(implementedBehaviorType, implementationType, serviceLifetime));
        }

        return this;
    }
    
    /// <summary>
    /// Registers an open stream behavior type against the <see cref="IStreamPipelineBehavior{TRequest,TResponse}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviorType">An open generic stream behavior type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenStreamBehavior(Type openBehaviorType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        if (!openBehaviorType.IsGenericType)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must be generic");
        }

        var implementedGenericInterfaces = openBehaviorType.GetInterfaces().Where(i => i.IsGenericType).Select(i => i.GetGenericTypeDefinition());
        var implementedOpenBehaviorInterfaces = new HashSet<Type>(implementedGenericInterfaces.Where(i => i == typeof(IStreamPipelineBehavior<,>)));

        if (implementedOpenBehaviorInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must implement {typeof(IStreamPipelineBehavior<,>).FullName}");
        }

        foreach (var openBehaviorInterface in implementedOpenBehaviorInterfaces)
        {
            StreamBehaviorsToRegister.Add(new ServiceDescriptor(openBehaviorInterface, openBehaviorType, serviceLifetime));
        }

        return this;
    }

    /// <summary>
    /// Register a closed request pre processor type
    /// </summary>
    /// <typeparam name="TServiceType">Closed request pre processor interface type</typeparam>
    /// <typeparam name="TImplementationType">Closed request pre processor implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPreProcessor<TServiceType, TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddRequestPreProcessor(typeof(TServiceType), typeof(TImplementationType), serviceLifetime);
    
    /// <summary>
    /// Register a closed request pre processor type
    /// </summary>
    /// <param name="serviceType">Closed request pre processor interface type</param>
    /// <param name="implementationType">Closed request pre processor implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPreProcessor(Type serviceType, Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        RequestPreProcessorsToRegister.Add(new ServiceDescriptor(serviceType, implementationType, serviceLifetime));

        return this;
    }

    /// <summary>
    /// Register a closed request pre processor type against all <see cref="IRequestPreProcessor{TRequest}"/> implementations
    /// </summary>
    /// <typeparam name="TImplementationType">Closed request pre processor implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPreProcessor<TImplementationType>(
        ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddRequestPreProcessor(typeof(TImplementationType), serviceLifetime);

    /// <summary>
    /// Register a closed request pre processor type against all <see cref="IRequestPreProcessor{TRequest}"/> implementations
    /// </summary>
    /// <param name="implementationType">Closed request pre processor implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPreProcessor(Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        var implementedGenericInterfaces = implementationType.FindInterfacesThatClose(typeof(IRequestPreProcessor<>)).ToList();

        if (implementedGenericInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{implementationType.Name} must implement {typeof(IRequestPreProcessor<>).FullName}");
        }

        foreach (var implementedPreProcessorType in implementedGenericInterfaces)
        {
            RequestPreProcessorsToRegister.Add(new ServiceDescriptor(implementedPreProcessorType, implementationType, serviceLifetime));
        }
        
        return this;
    }
    
    /// <summary>
    /// Registers an open request pre processor type against the <see cref="IRequestPreProcessor{TRequest}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviorType">An open generic request pre processor type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenRequestPreProcessor(Type openBehaviorType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        if (!openBehaviorType.IsGenericType)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must be generic");
        }

        var implementedGenericInterfaces = openBehaviorType.GetInterfaces().Where(i => i.IsGenericType).Select(i => i.GetGenericTypeDefinition());
        var implementedOpenBehaviorInterfaces = new HashSet<Type>(implementedGenericInterfaces.Where(i => i == typeof(IRequestPreProcessor<>)));

        if (implementedOpenBehaviorInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must implement {typeof(IRequestPreProcessor<>).FullName}");
        }

        foreach (var openBehaviorInterface in implementedOpenBehaviorInterfaces)
        {
            RequestPreProcessorsToRegister.Add(new ServiceDescriptor(openBehaviorInterface, openBehaviorType, serviceLifetime));
        }

        return this;
    }
    
    /// <summary>
    /// Register a closed request post processor type
    /// </summary>
    /// <typeparam name="TServiceType">Closed request post processor interface type</typeparam>
    /// <typeparam name="TImplementationType">Closed request post processor implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPostProcessor<TServiceType, TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddRequestPostProcessor(typeof(TServiceType), typeof(TImplementationType), serviceLifetime);
    
    /// <summary>
    /// Register a closed request post processor type
    /// </summary>
    /// <param name="serviceType">Closed request post processor interface type</param>
    /// <param name="implementationType">Closed request post processor implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPostProcessor(Type serviceType, Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        RequestPostProcessorsToRegister.Add(new ServiceDescriptor(serviceType, implementationType, serviceLifetime));

        return this;
    }
 
    /// <summary>
    /// Register a closed request post processor type against all <see cref="IRequestPostProcessor{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <typeparam name="TImplementationType">Closed request post processor implementation type</typeparam>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPostProcessor<TImplementationType>(ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
        => AddRequestPostProcessor(typeof(TImplementationType), serviceLifetime);
    
    /// <summary>
    /// Register a closed request post processor type against all <see cref="IRequestPostProcessor{TRequest,TResponse}"/> implementations
    /// </summary>
    /// <param name="implementationType">Closed request post processor implementation type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddRequestPostProcessor(Type implementationType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        var implementedGenericInterfaces = implementationType.FindInterfacesThatClose(typeof(IRequestPostProcessor<,>)).ToList();

        if (implementedGenericInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{implementationType.Name} must implement {typeof(IRequestPostProcessor<,>).FullName}");
        }

        foreach (var implementedPostProcessorType in implementedGenericInterfaces)
        {
            RequestPostProcessorsToRegister.Add(new ServiceDescriptor(implementedPostProcessorType, implementationType, serviceLifetime));
        }
        return this;
    }
    
    /// <summary>
    /// Registers an open request post processor type against the <see cref="IRequestPostProcessor{TRequest,TResponse}"/> open generic interface type
    /// </summary>
    /// <param name="openBehaviorType">An open generic request post processor type</param>
    /// <param name="serviceLifetime">Optional service lifetime, defaults to <see cref="ServiceLifetime.Transient"/>.</param>
    /// <returns>This</returns>
    public FlowRServiceConfiguration AddOpenRequestPostProcessor(Type openBehaviorType, ServiceLifetime serviceLifetime = ServiceLifetime.Transient)
    {
        if (!openBehaviorType.IsGenericType)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must be generic");
        }

        var implementedGenericInterfaces = openBehaviorType.GetInterfaces().Where(i => i.IsGenericType).Select(i => i.GetGenericTypeDefinition());
        var implementedOpenBehaviorInterfaces = new HashSet<Type>(implementedGenericInterfaces.Where(i => i == typeof(IRequestPostProcessor<,>)));

        if (implementedOpenBehaviorInterfaces.Count == 0)
        {
            throw new InvalidOperationException($"{openBehaviorType.Name} must implement {typeof(IRequestPostProcessor<,>).FullName}");
        }

        foreach (var openBehaviorInterface in implementedOpenBehaviorInterfaces)
        {
            RequestPostProcessorsToRegister.Add(new ServiceDescriptor(openBehaviorInterface, openBehaviorType, serviceLifetime));
        }

        return this;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use TypeFilter instead")]
    public Func<Type, bool> TypeEvaluator
    {
        get => TypeFilter;
        set => TypeFilter = value;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use MaxOpenGenericRequestParamCount instead")]
    public int MaxGenericTypeParameters
    {
        get => MaxOpenGenericRequestParamCount;
        set => MaxOpenGenericRequestParamCount = value;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use MaxOpenGenericRequestTypeCount instead")]
    public int MaxTypesClosing
    {
        get => MaxOpenGenericRequestTypeCount;
        set => MaxOpenGenericRequestTypeCount = value;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use MaxOpenGenericHandlerCount instead")]
    public int MaxGenericTypeRegistrations
    {
        get => MaxOpenGenericHandlerCount;
        set => MaxOpenGenericHandlerCount = value;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use GenericRegistrationTimeout instead")]
    public int RegistrationTimeout
    {
        get => GenericRegistrationTimeout;
        set => GenericRegistrationTimeout = value;
    }

    /// <summary>
    /// For compatibility with older code
    /// </summary>
    [Obsolete("Use AutoRegisterProcessors instead")]
    public bool AutoRegisterRequestProcessors
    {
        get => AutoRegisterProcessors;
        set => AutoRegisterProcessors = value;
    }
}

/// <summary>
/// Compatibility class for MediatR. All previous methods continue to work.
/// </summary>
public class MediatRServiceConfiguration : FlowRServiceConfiguration {}