# Architecture

```mermaid
flowchart LR
    subgraph eth["🔗  Ethereum"]
        ETH("Ethereum Node\nWebSocket RPC")
    end

    subgraph core["⚙️  Core Services"]
        direction TB
        subgraph indexer["Indexer Service"]
            IDX["Indexer"]
            IDX_STATE[/"State File (JSON)"/]
            IDX -->|persist last block| IDX_STATE
        end

        subgraph apiserver["API Server  ×2"]
            API["API Server"]
        end

        subgraph dashboard["Dashboard Service"]
            DASH["Dashboard"]
            SSE["SSE Hub"]
            UI["Static UI"]
            DASH --- SSE
            DASH --- UI
        end
    end

    subgraph storage["🗄️  Storage"]
        direction TB
        PG[("PostgreSQL")]
        RD[("Redis / Valkey")]
    end

    subgraph cdc["📨  CDC Pipeline"]
        direction TB
        DBZ["Debezium\nKafka Connect"]
        KF{{"Kafka"}}
        DBZ -->|publish| KF
    end


    subgraph gateway["🌐  Gateway"]
        GW["NGINX :80"]
    end

    BR(["👤 Browser"])

    ETH -->|"SubscribeNewHead\neth_getLogs"| IDX
    IDX -->|bulk INSERT| PG
    PG -->|WAL replication| DBZ
    KF -->|consume CDC| DASH

    BR -->|HTTPS| GW
    GW -->|"/api"| API
    GW -->|"/dashboard"| DASH
    GW -->|"/indexer"| IDX

    API -->|cache-aside| RD
    API -->|SQL query| PG
    SSE -->|SSE stream| BR
    UI -->|search API| API

    classDef svc fill:#2563eb,stroke:#1d4ed8,color:#fff,font-size:22px,padding:20px
    classDef db fill:#059669,stroke:#047857,color:#fff,font-size:22px,padding:20px
    classDef infra fill:#7c3aed,stroke:#6d28d9,color:#fff,font-size:22px,padding:20px

    classDef ext fill:#475569,stroke:#334155,color:#fff,font-size:22px,padding:20px
    classDef user fill:#0891b2,stroke:#0e7490,color:#fff,font-size:22px,padding:20px

    class IDX,API,DASH,SSE,UI svc
    class PG,RD db
    class DBZ,KF,GW infra

    class ETH,IDX_STATE ext
    class BR user
```

## Data Flows

1. **Indexing**: Ethereum → Indexer → PostgreSQL
2. **CDC**: PostgreSQL → Debezium → Kafka → Dashboard → SSE → Browser
3. **Query**: Browser → Gateway → API Server → Redis (cache-aside) → PostgreSQL
4. **UI**: Browser loads static assets from Dashboard, calls API Server for historical data
