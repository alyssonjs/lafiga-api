require 'rails_helper'

RSpec.describe "Characters", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/character/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /all" do
    it "returns http success" do
      get "/character/all"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/character/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/character/update"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /delete" do
    it "returns http success" do
      get "/character/delete"
      expect(response).to have_http_status(:success)
    end
  end

end
