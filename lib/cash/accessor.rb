module Cash
  module Accessor
    def self.included(a_module)
      a_module.module_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module ClassMethods
      def fetch(keys, options = {}, &block)
        case keys
        when Array
          cache_and_actual_keys = keys.inject({}) { |memo, key| memo[cache_key(key)] = key; memo }
          cache_keys = keys.collect {|key| cache_key(key)}
          
          hits = repository.get_multi(cache_keys)
          if (missed_cache_keys = cache_keys - hits.keys).any?
            actual_missed_keys = missed_cache_keys.collect {|missed_cache_key| cache_and_actual_keys[missed_cache_key]}
            misses = block.call(actual_missed_keys)

            hits.merge!(misses)
          end
          hits
        else
          repository.get(cache_key(keys), options[:raw]) || (block ? block.call : nil)
        end
      end

      def get(keys, options = {}, &block)
        case keys
        when Array
          fetch(keys, options) do |missed_keys|
            results = yield(missed_keys)
            results.each {|key, value| add(key, (value.size == 1 ? value.first : value), options)}
            results
          end
        else
          fetch(keys, options) do
            if block_given?
              result = yield(keys)
              value = result.is_a?(Hash) ? result[cache_key(keys)] : result
              add(keys, value, options)
              result
            end
          end
        end
      end

      def add(key, value, options = {})
        if repository.add(cache_key(key), value, options[:ttl] || 0, options[:raw]) == "NOT_STORED\r\n"
          yield if block_given?
        end
      end

      def set(key, value, options = {})
        repository.set(cache_key(key), value, options[:ttl] || 0, options[:raw])
      end

      def incr(key, delta = 1, ttl = 0)
        repository.incr(cache_key = cache_key(key), delta) || begin
          repository.add(cache_key, (result = yield).to_s, ttl, true) { repository.incr(cache_key) }
          result
        end
      end

      def decr(key, delta = 1, ttl = 0)
        repository.decr(cache_key = cache_key(key), delta) || begin
          repository.add(cache_key, (result = yield).to_s, ttl, true) { repository.decr(cache_key) }
          result
        end
      end

      def expire(key)
        repository.delete(cache_key(key))
      end

      def cache_key(key)
        ready = key =~ /#{name}:#{cache_config.version}/
        ready ? key : "#{name}:#{cache_config.version}/#{key.to_s.gsub(' ', '+')}"
      end
    end

    module InstanceMethods
      def expire
        self.class.expire(id)
      end
    end
  end
end
