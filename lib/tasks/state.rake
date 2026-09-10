namespace :kos do
  namespace :state do
    desc "Prepare production state and apply pending migrations safely"
    task prepare: :environment do
      unless Rails.env.production?
        raise Kos::State::Error, "kos:state:prepare requires RAILS_ENV=production"
      end

      Kos::State::Prepare.call
    end
  end
end
