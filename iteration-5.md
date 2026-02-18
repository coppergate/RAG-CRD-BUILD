## Allow the RAG request to be serviced by multiple node with different models

### Implement a target model selection mechanism in the RAG service
- the inbound request should specify the target model
- the inbound request should include a model identifier
- the RAG service should validate the model identifier against a predefined list of supported models
- the RAG service should route the request to the appropriate node based on the model identifier
- the RAG service should handle cases where the specified model is not available or not supported
- the RAG service should log the model selection process for monitoring and debugging purposes

### Implement a model selection API endpoint
- the API endpoint should accept the model identifier as a parameter
- the API endpoint should validate the model identifier against the predefined list of supported models
- the API endpoint should return the appropriate node for the specified model
- the API endpoint should handle cases where the specified model is not available or not supported
- the API endpoint should log the model selection process for monitoring and debugging purposes

### Implement a model selection middleware
- the middleware should utilize the PULSAR bus to route the request to the appropriate node
- the middleware should intercept incoming RAG requests
- the middleware should extract the model identifier from the request
- the middleware should validate the model identifier against the predefined list of supported models
- the middleware should route the request to the appropriate node based on the model identifier
- the middleware should handle cases where the specified model is not available or not supported
- the middleware should log the model selection process for monitoring and debugging purposes

### Add a model selection database table
- the database table should include columns for model identifier, node identifier, and last updated timestamp
- the database table should be created at startup
- the database table should be validated before use
- the database table should be updated dynamically if necessary

### Add a UI to define and maintain model selection
- the UI should provide basic CRUD
- the UI should provide a way to add model selection information to the database
- the UI should provide a way to update model selection information in the database
- the UI should provide a way to delete model selection information from the database
- the UI should log the model selection process for monitoring and debugging purposes
- the UI should have a way to determine if the input model identifier is valid
  
### Augment the current 'Ask the RAG' interface to support select one or more models to target
- the UI should provide a way to select one or more models to target
- the UI should validate the selected models against the predefined list of supported models
- the UI should route the request to the appropriate nodes based on the selected models
- the UI should handle cases where the specified models are not available or not supported
- the UI should log the model selection process for monitoring and debugging purposes

### Add support for the configuration discovery (add functionality to the services that acts like a 'ping')
- from the UI through to the each of the services add an endpoint that will allow the service to respond to a simple inquiry with its configuration and status information
- these endpoints should use the PULSAR bus to communicate with the services.
