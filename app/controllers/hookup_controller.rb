require 'http'
require 'google/api_client'
require 'date'

#GoogleCalendarのAOuth認証
class HookupController < ApplicationController
  
  # この↓一文がないとCSRF(Cross-Site Request Forgery)チェックでこけるので、APIをやりとりしているControllerには必要
  skip_before_filter :verify_authenticity_token
  
  #kke.remotelock@gmail.com
  @@googleAccountId = APP_CONFIG["google"]["user_name"]
  
  #クライアントID,クライアントシークレット,承認済みのリダイレクトURI,カレンダーIDを入力
  def setup
  end
  
  #上記変数を受取る
  def getcode
    
    @@clientId = params[:clientId]
    @@clientSecret = params[:clientSecret]
    @@calendarId = params[:calendarId]
    @@redirectUri = params[:redirectUri]
    
    #以下だと、入力文字列が認識されないようなのでコメントアウト
    #@@clientId = APP_CONFIG["google"]["client"] || params[:clientId].presence
    #@@clientSecret = APP_CONFIG["google"]["secret"] || params[:clientSecret]
    #@@calendarId = APP_CONFIG["google"]["calendar_id"] || params[:calendarId]
    #@@redirectUri = APP_CONFIG["webhost"]+'hookup/callback' || params[:redirectUri]
    
    #GoogleAccountテーブルに値を保存
    googleAccount = GoogleAccount.new(account_id: @@googleAccountId, client_id: @@clientId, client_secret: @@clientSecret, calendar_id:@@calendarId, redirect_uri:@@redirectUri )
    googleAccount.save
    
    #google認証のURLにリダイレクト
    url = 'https://accounts.google.com/o/oauth2/auth?client_id=' + @@clientId + '&redirect_uri=' + @@redirectUri + 
    '&scope=https://www.googleapis.com/auth/calendar&response_type=code&approval_prompt=force&access_type=offline'
    
    redirect_to(url)
  end
  
  
  #google認証後のリダイレクト先URI
  def callback
    #引数(=コード)を取得
    code = params[:code]
    
    clientId = GoogleAccount.find_by(account_id: @@googleAccountId).client_id
    clientSecret = GoogleAccount.find_by(account_id: @@googleAccountId).client_secret
    redirectUri = GoogleAccount.find_by(account_id: @@googleAccountId).redirect_uri
    
    #クライアントID,クライアントシークレット,承認済みのリダイレクトURI,コードから、リフレッシュトークンとアクセストークンを取得
    postbody = {
      :client_id => clientId,
      :client_secret => clientSecret,
      :redirect_uri => redirectUri,
      :grant_type => "authorization_code",
      :code => code
    }
    
    #HTTP.post(URL)でURLにpostリクエストを送る
    res = HTTP.headers("Content-Type" => "application/x-www-form-urlencoded").post("https://accounts.google.com/o/oauth2/token", :form => postbody )
	  
  	if res.code.to_s == "200"
  	    
    	j = ActiveSupport::JSON.decode( res )
    	  
    	@@accessToken = j["access_token"]
    	@@refreshToken = j["refresh_token"]
    	@@expiresIn = Time.now + j["expires_in"].second   # expires_in => 3600秒(1時間)
    	  
    	#GoogleTokenテーブルに値を保存
    	#if GoogleToken.find_by(key: @@clientId) == nil
      googleToken = GoogleToken.new(account_id: @@googleAccountId, access_token: @@accessToken, refresh_token:@@refreshToken, expire:@@expiresIn )
      googleToken.save
      #end
        
    else
      puts "Googleアクセストークンの取得に失敗しました。"
    end
  	  
  	createchannel
  	  
  	render action: 'createchannel'

  end
  
  
  #アクセストークンを利用してチャネルを作成
  def createchannel
    
    clientId = GoogleAccount.find_by(account_id: @@googleAccountId).client_id
    clientSecret = GoogleAccount.find_by(account_id: @@googleAccountId).client_secret
    refreshToken = GoogleToken.find_by(account_id: @@googleAccountId).refresh_token
    calendarId = GoogleAccount.find_by(account_id: @@googleAccountId).calendar_id
    
	  #GoogleApiを利用する
	  client = Google::APIClient.new
    client.authorization.client_id = clientId
    client.authorization.client_secret = clientSecret
    client.authorization.refresh_token = refreshToken
    client.authorization.fetch_access_token!
    
    service = client.discovered_api('calendar', 'v3')
    
    res = client.execute!(
      api_method: service.events.watch,
      parameters: { calendarId: calendarId },
      body_object: {
        id: SecureRandom.uuid(),
        type: 'web_hook',
        address: URI.encode(APP_CONFIG["webhost"]+'notifications/callback')
      }
    )
	  
	  @status = res.status
	  
	  if res.status.to_s == "200"
      @status = "認証に成功しました"
      #チャネルのIDと、カレンダーIDの対応を保存
      #channel_id = ""
      #calendar_id = @@calendarId
      #expires_in = DateTime.now + 7.day
      #channel = GoogleChannel.new(:channel_id => channel_id ,:calendar_id => calendar_id,:expires_in => expires_in )
      #channel.save
      
      #カレンダーIDが含まれているURIを取得.以下は取得例
  	  #"https://www.googleapis.com/calendar/v3/calendars/i8a77r26f9pu967g3pqpubv0ng@group.calendar.google.com/events?maxResults=250&alt=json"
  	  j = ActiveSupport::JSON.decode( res.body )
  	  resourceUri = j["resourceUri"]
	    
      #チャネルのIDと、カレンダーIDの対応を保存
      googleChannel = GoogleChannel.new(channel_id: j["id"], calendar_id: calendarId, access_token: "", refresh_token: refreshToken, expires_in: DateTime.now + 7.day )
      googleChannel.save
      
    else
	  	@status = "認証に失敗しました"
	  end
	  
	  puts(res.body)
	  
  end
  
  
end
