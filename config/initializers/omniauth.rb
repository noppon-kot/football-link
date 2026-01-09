OmniAuth.config.allowed_request_methods = [:get, :post]

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :line,
           ENV["LINE_CHANNEL_ID"],
           ENV["LINE_CHANNEL_SECRET"]
end
