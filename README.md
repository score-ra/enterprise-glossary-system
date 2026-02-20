# Enterprise Glossary Management System (EGMS)

A centralized, URI-based enterprise glossary that serves as the single source of truth for organizational terminology, accessible to both humans and AI systems.

## Problem

Teams use different terms for the same concepts, glossary terms are scattered across wikis, Confluence, spreadsheets, and READMEs, and AI systems receive inconsistent context leading to poor responses.

## Key Objectives

1. **Standardization** — One authoritative source for all company terminology
2. **Accessibility** — Easily discoverable and queryable by all stakeholders
3. **AI Integration** — Machine-readable (RDF/semantic web) format for AI agents
4. **Maintainability** — Version control and audit trails
5. **Scalability** — Support thousands of terms across departments and domains
6. **Integration** — API access for embedding in documentation, systems, and tools

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Platform | [SKOSMOS](https://skosmos.org/) (open-source, semantic web-native) |
| Storage | [Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/) (RDF triple store) |
| Infrastructure | Cloud hosting (AWS/GCP/Azure) |

## Project Structure

```
enterprise-glossary-system/
├── docs/                  # Documentation
│   ├── design-architecture.md
│   └── prds/
│       └── prd.md         # Product Requirements Document
├── LICENSE
└── README.md
```

## Getting Started

See the [Design & Implementation Guide](docs/design-architecture.md) for architecture details and the [PRD](docs/prds/prd.md) for full requirements.

## License

This project is licensed under the MIT License.