module SwaggerYard
  class OpenAPI < Swagger
    def to_h
      metadata.merge(definitions)
    end

    def model_path
      '#/components/schemas/'
    end

    def metadata
      metadata = {
        'openapi' => '3.0.0',
        'info' => Info.new.to_h,
        'servers' => [{
          'url' => SwaggerYard.config.api_base_path,
          'description' => SwaggerYard.config.api_base_path_description
        }],
        'security' => security_requirement,
      }
      metadata["externalDocs"] = external_docs if external_docs
      metadata
    end

    def definitions
      defs = {
        "paths" => paths(specification.path_objects),
        "tags" => tags(specification.tag_objects),
        "components" => components
      }
      webhooks = paths(specification.path_objects(for_webhooks: true))
      defs["x-webhooks"] = webhooks if webhooks.present?
      defs["x-tagGroups"] = specification.tag_groups if specification.tag_groups
      defs
    end

    def components
      {
        "schemas" => models(specification.model_objects),
        "securitySchemes" => security_schemes(specification.security_objects)
      }
    end

    def parameters(params)
      params.select { |param| param.param_type != 'body' }.map do |param|
        { "name"        => param.name,
          "description" => param.description,
          "required"    => param.required,
          "in"          => param.param_type
        }.tap do |h|
          schema = param.type.schema_with(model_path: model_path)
          h["schema"] = schema
          h["explode"] = true if !Array(param.allow_multiple).empty? && schema["items"]
        end
      end
    end

    def operation(op)
      op_hash = super
      if body_param = op.parameters.detect { |p| p.param_type == 'body' }
        op_hash['requestBody'] = {
          'description' => body_param.description,
          'content' => {
            'application/json' => {
              'schema' => body_param.type.schema_with(model_path: model_path)
            }
          }
        }
      end
      op_hash
    end

    def response(resp, op)
      {}.tap do |h|
        h['description'] = resp && resp.description || op.summary || ''
        if resp && resp.type && (schema = resp.type.schema_with(model_path: model_path))
          h['content'] = { 'application/json' => { 'schema' => schema } }
          h['content']['application/json']['example'] = resp.example if resp.example
        end
      end
    end

    def security_requirement
      security_defs(specification.security_objects).map do |name, _|
        { name => [] }
      end
    end


    def security_schemes(security_objects)
      defs = security_defs(security_objects)
      Hash[defs.map do |name, d|
             [name, map_security(d)]
           end]
    end

    def security(obj)
      case obj.type
      when /api_?key/i
        { 'type' => 'apiKey', 'name' => obj.key, 'in' => obj.name }
      when /bearer/i
        { 'type' => obj.type, 'name' => obj.name, 'format' => obj.key }
      else
        { 'type' => obj.type, 'name' => obj.name }
      end.tap do |result|
        result['description'] = obj.description if obj.description && !obj.description.empty?
      end
    end

    def map_security(h)
      h = Hash[h.map { |k, v| [k.to_s, v] }] # quick-n-dirty stringify keys
      case type = h['type'].to_s
      when 'apiKey', 'http'
        h
      when 'oauth2'
        # convert from swagger2-style oauth2
        if (authUrl = h.delete('authorizationUrl')) && (flow = h.delete('flow'))
          { 'type' => 'oauth2', 'flows' => {
              flow => { 'authorizationUrl' => authUrl } } }.tap do |result|
            (h.keys - ['type']).each do |t|
              result['flows'][flow][t] = h[t]
            end
            result['flows'][flow]['scopes'] = {} unless result['flows'][flow]['scopes']
          end
        else
          h
        end
      else
        { 'type' => 'http', 'scheme' => type }.tap do |result|
          result['bearerFormat'] = h['format'] if h['format']
        end
      end.tap do |result|
        result['description'] = h['description'] unless h['description'].nil? || h['description'].empty?
      end
    end
  end
end
