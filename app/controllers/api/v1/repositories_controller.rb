module Api
  module V1
    class RepositoriesController < BaseController
      def create
        body = mutation_body
        return if performed?

        inspection = -> { RepositoryRegistration::Inspect.call(body) }
        execute_mutation(body, status: :ok, serialize: Serializer.method(:repository), prepare: inspection) do |_key, observed|
          RepositoryRegistration::Register.call(observed)
        end
      end
    end
  end
end
