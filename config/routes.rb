# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

get 'patchnotes/index', to: 'patchnotes#index'

resources :projects do
    resources :patchnotes, :controller => 'patchnotes', :as => 'patchnotes'
end

resources :issues do
  resources :patch_notes, only: [:new, :create] do
    collection do
      post :skip
      post :unskip
    end
  end
end
resources :patch_notes, only: [:edit, :update, :destroy]
