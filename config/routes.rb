# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

get 'patchnotes/index', to: 'patchnotes#index'

resources :projects do
    resources :patchnotes, :controller => 'patchnotes', :as => 'patchnotes'
end