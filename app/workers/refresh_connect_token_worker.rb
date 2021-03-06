class RefreshConnectTokenWorker
  include Sidekiq::Worker
  include Sidetiq::Schedulable
  
  # 2時間以内に定期実行⇒とりあえず1時間毎
  recurrence do
    hourly(1)
  end

  def perform
    # LS Connectのアクセストークンを順次参照
    ConnectToken.find_each do |connect_token|
      connect_token.refresh
    end
    
    puts DateTime.now
    puts 'Sidekiq実行:ConnectAccessToken更新'
  end
end
