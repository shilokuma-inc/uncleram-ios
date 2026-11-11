#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Developer Portal に Bundle ID（App ID）を登録する。2 回目以降は確認だけで何もしない。
#
# Bundle ID は Export（-allowProvisioningUpdates）でも自動で登録されるが、このアプリは 1 つの App ID を iOS と macOS で使う
# （ユニバーサル購入のため）。プラットフォームを UNIVERSAL にして、archive の前に API で登録しておく。
# 登録すると、App Store Connect の「新規 App」のバンドル ID の候補にも出る。
#
# iCloud・Game Center などの capability は、その機能を入れるときにここで有効にする（idfa-vault-ios の同名のスクリプトを参照）。
#
# 使い方（環境変数で渡す）:
#   BUNDLE_ID=jp.shilokuma.MyApp APP_NAME="My App" \
#   API_KEY_PATH=AuthKey_XXXXXXXXXX.p8 APPLE_API_KEY_ID=XXXXXXXXXX APPLE_API_ISSUER_ID=xxxxxxxx-... \
#   ruby .github/scripts/ensure-bundle-id.rb
#
# Ruby の標準ライブラリだけで動く（gem のインストールは不要）。API の共通処理は app_store_connect.rb にある。

require_relative 'app_store_connect'

def find_bundle_id(identifier, token)
  json = AppStoreConnect.request(
    :get, '/v1/bundleIds',
    token: token,
    query: { 'filter[identifier]' => identifier, 'fields[bundleIds]' => 'identifier,name,platform', 'limit' => '200' }
  )
  # filter は前方一致でも返るので、identifier が一致するものだけを見る
  json.fetch('data').find { |bundle| bundle.dig('attributes', 'identifier') == identifier }
end

# 1 つの App ID を iOS と macOS で使うので UNIVERSAL で登録する。受け付けられなければ IOS で登録し直す
def register_bundle_id(identifier, name, token)
  %w[UNIVERSAL IOS].each do |platform|
    body = { data: { type: 'bundleIds', attributes: { identifier: identifier, name: name, platform: platform } } }
    begin
      return AppStoreConnect.request(:post, '/v1/bundleIds', token: token, body: body).fetch('data')
    rescue AppStoreConnect::Error => e
      raise unless platform == 'UNIVERSAL' && e.status.to_s == '409'

      puts "::notice::platform UNIVERSAL では登録できなかったため、IOS で登録し直します（HTTP #{e.status}）"
    end
  end
end

bundle_id = AppStoreConnect.env!('BUNDLE_ID')
# Bundle ID の名前に使えるのは英数字と空白だけ
app_name = AppStoreConnect.env!('APP_NAME').gsub(/[^A-Za-z0-9 ]/, ' ').squeeze(' ').strip
token = AppStoreConnect.token_from_env

begin
  bundle = find_bundle_id(bundle_id, token)
  if bundle
    puts "Bundle ID は登録済みです: #{bundle_id}（#{bundle.dig('attributes', 'name')}、#{bundle.dig('attributes', 'platform')}）"
  else
    bundle = register_bundle_id(bundle_id, app_name.empty? ? bundle_id.tr('.', ' ') : app_name, token)
    message = "Bundle ID を登録しました: #{bundle_id}（#{bundle.dig('attributes', 'name')}、#{bundle.dig('attributes', 'platform')}）"
    puts "::notice::#{message}"
    AppStoreConnect.write_summary("## Bundle ID を登録しました\n\n#{message}")
  end
rescue AppStoreConnect::Error => e
  abort "::error::#{e.message}"
end
