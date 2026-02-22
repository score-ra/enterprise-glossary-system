vcl 4.1;

backend default {
    .host = "fuseki";
    .port = "3030";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 10s;
}

sub vcl_recv {
    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Only cache SPARQL query endpoints (read-only)
    if (req.url ~ "^/skosmos/(sparql|query)") {
        return (hash);
    }

    # Pass through all write operations (update, data, upload)
    if (req.url ~ "^/skosmos/(update|data|upload)") {
        return (pass);
    }

    # Pass through Fuseki admin endpoints
    if (req.url ~ "^/\$") {
        return (pass);
    }

    # Default: try to cache
    return (hash);
}

sub vcl_backend_response {
    # Cache SPARQL query responses for 5 minutes
    # Override Fuseki's Cache-Control: no-cache,no-store headers
    if (bereq.url ~ "^/skosmos/(sparql|query)") {
        set beresp.ttl = 5m;
        set beresp.grace = 30s;
        set beresp.uncacheable = false;
        unset beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "public, max-age=300";
    }

    # Do not cache error responses
    if (beresp.status >= 400) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    }
}

sub vcl_deliver {
    # Add cache hit/miss header for debugging
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
