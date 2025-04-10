namespace FlowR;

/// <summary>
/// Marker interface for streaming requests
/// </summary>
/// <typeparam name="TResponse">Response type</typeparam>
public interface IStreamRequest<out TResponse> : IBaseRequest { }
