defmodule DateParser do
  @months %{
    "January" => 1, "February" => 2, "March" => 3, "April" => 4,
    "May" => 5, "June" => 6, "July" => 7, "August" => 8,
    "September" => 9, "October" => 10, "November" => 11, "December" => 12
  }

  def parse_date(date_string) do
    regex = ~r/^(\d+)(?:st|nd|rd|th)\s+([A-Za-z]+)\s+(\d{2})$/
    case Regex.run(regex, date_string) do
      [_, day, month, year] ->
        year = String.to_integer(year) + 2000  # Assuming 20 means 2020+
        day = String.to_integer(day)
        month = Map.get(@months, month)

        if month do
          Date.new(year, month, day)
        else
          {:error, :invalid_month}
        end
      _ ->
        {:error, :invalid_format}
    end
  end
end


defmodule TestProject do
  @moduledoc """
  Extracts meeting details from an HTML file.
  """
  require Logger

  @start_id "LATEST_MEETING_ID"
  @cookie "COOKIE"

  def fetch_all_meetings(start_id \\ @start_id, result \\ []) do
    IO.puts("[#{length(result) + 1}] Loading meeting with id:#{start_id}")

    meeting = fetch_meeting(start_id)

    IO.puts(meeting |> Jason.encode!)

    new_result = [meeting] ++ result

    if meeting.previous_meeting_id do
      fetch_all_meetings(meeting.previous_meeting_id, new_result)
    else
      new_result
    end
  end

  def fetch_meeting(id) do
    fetch_meeting_html(id)
    |> extract_meeting_info()
  end

  def fetch_meeting_html(id) do
    headers = [
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"},
      {"Accept-Language", "pl,en;q=0.9,pl-PL;q=0.8,en-US;q=0.7,it;q=0.6,it-IT;q=0.5"},
      {"Connection", "keep-alive"},
      {"Cookie", @cookie},
      {"Referer", "https://tmclub.eu/view_meeting.php?t=#{id}"},
      {"Sec-Fetch-Dest", "document"},
      {"Sec-Fetch-Mode", "navigate"},
      {"Sec-Fetch-Site", "same-origin"},
      {"Sec-Fetch-User", "?1"},
      {"Upgrade-Insecure-Requests", "1"},
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"},
      {"sec-ch-ua", "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\""},
      {"sec-ch-ua-mobile", "?0"},
      {"sec-ch-ua-platform", "\"macOS\""}
    ]

    case HTTPoison.get("https://tmclub.eu/view_meeting.php?t=#{id}", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> body
      {:error, reason} -> Logger.error("Failed to fetch HTML: #{inspect(reason)}"); nil
    end
  end

  def extract_meeting_info(html) do
    {:ok, document} = Floki.parse_document(html)

    header = document |> Floki.find(".gen b") |> Enum.map(fn x -> Floki.text(x) end)
    meeting_name_index = if length(header) == 4, do: 3, else: 2
    meeting_name = header |> Enum.at(meeting_name_index)
    meeting_number = if header |> Enum.at(1) |> String.starts_with?("#"), do: header |> Enum.at(1) |> String.split("#") |> Enum.at(1) |> String.to_integer(), else: "N/A"

    # header = document |> Floki.find(".gen")|> Floki.text() |> String.split("\n")
    # meeting_name = header |> Enum.at(2) |> String.split("Meeting Theme") |> Enum.at(1) |> String.trim
    # meeting_number = header |> Enum.at(1) |> String.split(": ") |> Enum.at(1) |> String.split(" - ") |> Enum.at(0) |> String.split("#") |> Enum.at(1) |> String.to_integer()


    speech_titles = for i <- 1..10, document |> Floki.find("#speechdetail_#{i}") |> Floki.text() != "", do: document |> Floki.find("#speechdetail_#{i} > table > tr > td") |> Enum.map(fn x -> x |> Floki.text() end) |> Enum.at(0)
    speech_authors = (for i <- ["1st", "2nd", "3rd", "4th", "5th", "6th"], do: document |> Floki.find("tr") |> Enum.filter(fn x -> x |> Floki.text() |> String.starts_with?("#{i} Mówca") end) |> Enum.map(fn x -> x |> Floki.find("a") |> Floki.text() end)) |> Enum.map(fn x -> x|> Enum.at(0) end) |> Enum.filter(fn x -> !is_nil(x) end)
    speeches = Enum.zip(speech_authors, speech_titles) |> Enum.map(fn {x, y} -> %{author: x, title: y} end)
    meeting_date_string = document |> Floki.find(".maintitle") |> Floki.text() |> String.split(" at ") |> Enum.at(0)
    {:ok, meeting_date} = DateParser.parse_date(meeting_date_string)

    participants =
      document
      |> Floki.find("#status_div_ span.nav")
      |> Enum.map(&Floki.text/1)
      |> Enum.reject(&(&1 == ""))

    previous_meeting_id = get_previous_meeting_id(document)

    %{meeting_name: meeting_name, meeting_date: meeting_date, meeting_number: meeting_number, participants: participants, speeches: speeches, previous_meeting_id: previous_meeting_id}
    # |> Jason.encode!
  end

  def get_previous_meeting_id(document) do
    link = document |> Floki.find("a") |> Enum.filter(fn x -> x |> Floki.text() == "Previous" end) |> Enum.at(0)

    if link do
      link |> Floki.attribute("href") |> Enum.at(0) |> String.split("t=") |> Enum.at(1)
    end
  end
end
