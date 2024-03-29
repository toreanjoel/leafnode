defmodule LeafNode.Servers.ExecutionServer do
  @moduledoc """
    The execution server that will be used to create instances when executing a document
  """
  use GenServer
  require Logger
  alias LeafNode.Servers.ExecutionHistoryServer, as: ExecutionHistoryServer

  @doc """
    State the server with base argument data
  """
  def start_link(id) do
    # we dont give a constant name so we can run multiple instances of this
    GenServer.start_link(__MODULE__, %{}, name: String.to_atom("execution_process_" <> id))
  end

  @doc """
    Initialize the state of the server
  """
  def init(state) do
    {:ok, state}
  end

  @doc """
    Here we store the input to the execution payload instance so we can reference later
  """
  def handle_call(:get_input, _from, state) do
    {:reply, Map.get(state, "input", %{}), state}
  end

  @doc """
    Here we listen for the execution of the document
  """
  def handle_call({:execute, document_id, payload}, _form, state) do
    # start the agent server for this document -  make sure its started
    ExecutionHistoryServer.start_link(document_id)

    # get the document in memory if it exists
    {status, document} = LeafNode.Core.Documents.get_document(document_id)

    case status do
      :ok ->
        # Here we get all the details of texts that has psuedo code associated with it
        {status, texts} = LeafNode.Core.Text.list_texts(document_id)
        text_data = case status do
          :ok -> Enum.filter(texts, fn item -> !is_nil(item.pseudo_code) end)
          _ -> []
        end
        doc_with_texts = Map.put(document, :texts, text_data)

        {status, result} = start_execution(doc_with_texts, payload)
        # Stop the history server instance here
        GenServer.stop(String.to_atom("history_" <> document_id), :normal)
        {:stop, :normal, {status, result}, state}
      _ ->
        # Stop the history server instance here
        GenServer.stop(String.to_atom("history_" <> document_id), :normal)
        {:stop, :normal, {:error, "There was an error executing the document"}, state}
    end
  end

  @doc """
    We need to go through the relevant document to execute the code and store result
  """
  defp start_execution(document, payload) do
    # Flush the execution history before updating the data
    GenServer.call(String.to_atom("history_" <> document.id), :flush_history)
    # get the functions - and attempt excute
    Enum.each(document.texts, fn text ->
      pseudo_code = text.pseudo_code
      LeafNode.Core.Code.execute(pseudo_code, document.id, text.id, payload)
    end)

    {:ok, %{
      "document" => document,
      "results" => GenServer.call(String.to_atom("history_" <> document.id), :get_history)
    }}
  end
end
