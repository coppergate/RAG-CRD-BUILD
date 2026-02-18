## Our next step is going to be to enhance the rag-web-ui and backing services.
#### NB: THE GOAL IS TO SUPPORT INTERACTIVE CODING SESSIONS. WE WANT TO BE ABLE TO PULL RESULTS FROM MULTIPLE LLMs USING A DEFINED CONTEXT.

### First we need to enhance the UI
- 1 page to support the ingestion and tagging of data from files
- 1 page to run a chat with the LLM.

### Move the 'Ask the RAG' section onto its own page
1. the page should allow starting or continuing a 'session'
   1. we need to be able to select from previous 'sessions'
      1. implement this as a pop-up dialog displaying the recorded sessions in reverse chronological order
   3. we need to be able to store some additional information regarding the 'session'
      1. we need both a name and a short description 
      2. implement these as text boxes. 
2. the 'session' will include a set of 'tags' from the ingestion to specify additional context
    1. we need to be able to select from 'tags' to include in the context
        1. implement this as a multi-select dropdown
3. the 'session' will include a 'running history' of the chat session
   1. we should be able to restrict the displayed 'running history' by date range
   2. we should be able to search the 'running history' by 'key words'
4. the 'running history' will include the user prompts and the system responses
   1. we want to store the prompts and responses in separate tables
   2. we want to be able to attach multiple response records to a single prompt
   3. we want a sequence number on the response records
5. the 'running history' will a date/timestamp
6. each entry in the 'running history' will have a unique identifier for future reference
7. the 'running history' will be stored in the timescaledb

** the rest of the rag ingestion page can remain as it is.

### Layout for the 'Ask the RAG'
1. The current interaction should be in a text box at the top of the screen
2. follow the same general look and feel as the ingestion page
3. The 'running history' should be displayed in a scrollable list below the current interaction text box in reverse chronological order
    1. there should be standard timeframes to select from (last minute, last 5 minutes, last 15 minutes, ...)
4. The 'running history' should be searchable by date range and 'key words'
5. There should be UI to add and remove 'Tags' from the current context

** a couple of things to note:
- we need to ensure that the UI for adding and removing tags is intuitive and easy to use
- we should consider a future possibility of implementing a feature to allow users to save their current context for future use
- we should consider future enhancements that will require more complex UI interactions, including:
  - agentic application of results from the session.
  - integration with other tools and services


### Server architecture
1. all communication should be via REST APIs to the PULSAR message bus and from the BUS to the microservices
   1. if we need to modify the current interfaces we should do that now.
2. the 'Ask the RAG' page should be a separate microservice
3. the 'Ask the RAG' microservice should be able to communicate with the ingestion microservice
   1. enhance the ingestion microservice so that it can receive messages from the 'Ask the RAG' microservice via the PULSAR bus
   2. the 'Ask the RAG' microservice should be able to communicate with the ingestion microservice via the PULSAR bus
4. the 'Ask the RAG' microservice should be able to communicate with the timescaledb microservice 
   1. setup a PULSAR topic for the 'Ask the RAG' microservice
   2. enable a service to handle requests from the PULSAR bus to timescaledb
5. we want to be able to communicate with the 'Ask the RAG' microservice from other microservices
   1. make the 'Ask the RAG' microservice so that it can receive messages from other microservices via the PULSAR bus

If there are any questions or concerns, we need to discuss them before you commit to any changes.
Please provide a break-down of the proposed changes before starting any code changes.
