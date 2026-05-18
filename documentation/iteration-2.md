## ingestion
### enhance the organization and retrieval mechanism for the 'ingested code'
- using the postgresql (timescaledb) database 
  - add a set of tables that store tag information and relate to s3 buckets
    - we want to keep track of each code ingestion we perform 
      - assign a unique identifier to each ingestion
          - create a 'code_ingestion' table with columns for ingestion_id, timestamp, and s3_bucket_id
    - we want a list of tags that can be applied to each ingestion
      - we want a many-to-one relationship between tags and the code bucket
        - create a 'tag' table with columns for tag_id and tag_name
        - create a 'code_ingestion_tag' table with columns for ingestion_id and tag_id
- update the UI to allow the user to create and/or select code embedding tags when ingesting code
  - implement the database interface to support tag creation and selection
  - implement session tag selection and association mechanisms
###  enhance the vector storage based on the ingested s3 data
- we are currently using QDrant vector databases to store and retrieve code embeddings
  - enhance the current structure
    - create a 'code_embedding' table with columns for ingestion_id, embedding_vector, and other relevant metadata
    - implement efficient querying and retrieval mechanisms for code embeddings based on a set of tags
    - create a 'code_embedding_tag' table with columns for embedding_id and tag_id
  - configure a mechanism to synchronize code embedding ingestion tags from the 'code_ingestion_tag' table in the postgres database to the QDrant vector database
### enhance the session management currently in the timescaledb
- create a structure in the timescaledb to allow the user to select code embedding tags for use in a session
  - create a 'session' table with columns for session_id, user_id, and session_start_time
  - implement session expiration and cleanup mechanisms
  - implement session tag selection and association mechanisms