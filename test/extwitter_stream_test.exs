defmodule ExTwitterStreamTest do
  use ExUnit.Case, async: false
  import Mock

  @mock_tweet_json    File.read!("fixture/mocks/tweet.json")
  @mock_limit_json    File.read!("fixture/mocks/limit.json")
  @mock_deleted_tweet File.read!("fixture/mocks/deleted_tweet.json")
  @mock_stall_warning File.read!("fixture/mocks/stall_warning.json")

  setup_all do
    ExVCR.Config.filter_url_params(true)
    ExVCR.Config.filter_sensitive_data("oauth_signature=[^\"]+", "<REMOVED>")
    ExVCR.Config.filter_sensitive_data("guest_id=.+;", "<REMOVED>")

    ExTwitter.configure(
      consumer_key:        System.get_env("TWITTER_CONSUMER_KEY"),
      consumer_secret:     System.get_env("TWITTER_CONSUMER_SECRET"),
      access_token:        System.get_env("TWITTER_ACCESS_TOKEN"),
      access_token_secret: System.get_env("TWITTER_ACCESS_SECRET")
    )
    TestHelper.TestStore.start
    :ok
  end

  setup do
    TestHelper.TestStore.set([])
    :ok
  end

  test_with_mock "gets Twitter sample stream", :oauth,
    [get: fn(_url, _params, _consumer, _access_token, _access_token_secret, _options) ->
      request_id = make_ref
      TestHelper.TestStore.set({self, request_id})
      {:ok, request_id}
    end] do

    # Process stream on different process.
    parent = self
    spawn(fn() ->
      stream = ExTwitter.stream_sample
      tweet = Enum.take(stream, 1) |> List.first
      send parent, {:ok, tweet}
    end)

    # Send mock data after short wait.
    wait_async_request_initialization
    send_mock_data(TestHelper.TestStore.get, @mock_tweet_json)

    # Verify result.
    receive do
      {:ok, tweet} ->
        assert tweet.text =~ ~r/sample tweet text/
    end
  end

  test_with_mock "gets Twitter filter stream", :oauth,
    [post: fn(_url, _params, _consumer, _access_token, _access_token_secret, _options) ->
      request_id = make_ref
      TestHelper.TestStore.set({self, request_id})
      {:ok, request_id}
    end] do

    # Process stream on different process.
    parent = self
    spawn(fn() ->
      stream = ExTwitter.stream_filter(follow: "twitter")
      tweet = Enum.take(stream, 1) |> List.first
      send parent, {:ok, tweet}
    end)

    # Send mock data after short wait.
    wait_async_request_initialization
    send_mock_data(TestHelper.TestStore.get, @mock_tweet_json)

    # Verify result.
    receive do
      {:ok, tweet} ->
        assert tweet.text =~ ~r/sample tweet text/
    end
  end

  test_with_mock "gets twitter stream messages", :oauth,
      [post: fn(_url, _params, _consumer, _access_token, _access_token_secret, _options) ->
      request_id = make_ref
      TestHelper.TestStore.set({self, request_id})
      {:ok, request_id}
    end] do

    # Process stream on different process.
    parent = self
    spawn(fn() ->
      stream = ExTwitter.stream_filter(track: "twitter", receive_messages: true)
      tweets = Enum.take(stream, 3)
      send parent, {:ok, tweets}
    end)

    # Send mock data after short wait.
    wait_async_request_initialization
    send_mock_data(TestHelper.TestStore.get, @mock_limit_json)
    send_mock_data(TestHelper.TestStore.get, @mock_deleted_tweet)
    send_mock_data(TestHelper.TestStore.get, @mock_stall_warning)

    # Verify result.
    receive do
      {:ok, tweets} ->
        [limit, deleted_tweet, stall_warning] = tweets
        assert limit.track == 542
        assert deleted_tweet.status[:id] == 1234
        assert stall_warning.code == "FALLING_BEHIND"
    end
  end

  test "stream control succeeds" do
    parent = self
    pid = spawn(fn ->
      receive do
        {:control_stop, _pid} -> send parent, :ok
      after
        50 -> :timeout
      end
    end)

    assert ExTwitter.stream_control(pid, :stop, timeout: 50) == :ok
  end

  test "stream control timeouts after 10 milliseconds" do
    assert ExTwitter.stream_control(self, :stop, timeout: 10) == :timeout
  end

  defp wait_async_request_initialization do
    :timer.sleep(100) # Put small wait for mocking library to become ready.
  end

  defp send_mock_data({pid, request_id}, json) do
    headers = [{'connection', 'close'}, {'date', 'Sun, 06 Jul 2014 14:48:13 UTC'},
               {'transfer-encoding', 'chunked'}, {'content-type', 'application/json'},
               {'x-connection-hash', '4be738c31e867bd602893fb3a320e55e'}]


    send pid, {:http, {request_id, :stream_start, headers}}
    send pid, {:http, {request_id, :stream, json}}
  end
end
