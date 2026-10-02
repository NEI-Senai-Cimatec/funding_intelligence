// ============================================================================
// Funding Intelligence - Autenticação Supabase, Sessão e Interface de Acesso
// SENAI CIMATEC – Núcleo de Economia Industrial (NEI)
// ============================================================================

(function() {
  'use strict';

  // 1. Funções Globais de Submissão de Formulário (sempre disponíveis)
  window.submitLoginForm = function() {
    var emailInput = document.getElementById('login_email');
    var pwdInput = document.getElementById('login_password');
    var errBox = $('#auth_login_error_box');
    var errText = $('#auth_login_error_text');
    var btn = $('#btn_login_submit');

    var email = emailInput ? emailInput.value.trim() : '';
    var pwd = pwdInput ? pwdInput.value : '';

    if (!email || !pwd) {
      errText.text('Por favor, informe seu e-mail institucional e senha.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    errBox.hide();

    // Feedback visual imediato e animação no botão
    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Entrando na plataforma...</span>');

    var payload = { email: email, password: pwd, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('login_email', email);
      Shiny.setInputValue('login_password', pwd);
      Shiny.setInputValue('btn_login_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('login_email', email);
          Shiny.setInputValue('login_password', pwd);
          Shiny.setInputValue('btn_login_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');
          errText.text('Conectando ao servidor... Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  window.submitSignupForm = function() {
    var emailInput = document.getElementById('signup_email');
    var pwdInput = document.getElementById('signup_password');
    var pwdConfInput = document.getElementById('signup_password_confirm');
    var errBox = $('#auth_signup_error_box');
    var errText = $('#auth_signup_error_text');
    var btn = $('#btn_signup_submit');

    var email = emailInput ? emailInput.value.trim() : '';
    var pwd = pwdInput ? pwdInput.value : '';
    var pwdConf = pwdConfInput ? pwdConfInput.value : '';

    if (!email || !pwd) {
      errText.text('Por favor, informe seu e-mail institucional e defina uma senha.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd !== pwdConf) {
      errText.text('As senhas digitadas não coincidem.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd.length < 6) {
      errText.text('A senha deve conter no mínimo 6 caracteres.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    errBox.hide();

    // Feedback visual imediato e animação no botão
    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Cadastrando na plataforma...</span>');

    var payload = { email: email, password: pwd, password_confirm: pwdConf, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('signup_email', email);
      Shiny.setInputValue('signup_password', pwd);
      Shiny.setInputValue('signup_password_confirm', pwdConf);
      Shiny.setInputValue('btn_signup_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('signup_email', email);
          Shiny.setInputValue('signup_password', pwd);
          Shiny.setInputValue('signup_password_confirm', pwdConf);
          Shiny.setInputValue('btn_signup_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');
          errText.text('Conectando ao servidor... Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  // 2. Função de Alternância de Abas Instantânea (Entrar vs Criar Conta)
  window.switchAuthTab = function(mode) {
    $('.auth-tab-btn').removeClass('active');
    $('.auth-tab-btn[data-mode="' + mode + '"]').addClass('active');

    var formLogin = document.getElementById('auth_form_login');
    var formSignup = document.getElementById('auth_form_signup');

    // Limpa caixas de erro ao trocar de aba
    $('#auth_login_error_box, #auth_signup_error_box').hide();

    // Reseta botões se estiverem em loading
    var btnLogin = $('#btn_login_submit');
    btnLogin.prop('disabled', false).removeClass('loading');
    btnLogin.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');

    var btnSignup = $('#btn_signup_submit');
    btnSignup.prop('disabled', false).removeClass('loading');
    btnSignup.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');

    if (mode === 'signup') {
      if (formLogin) formLogin.style.display = 'none';
      if (formSignup) formSignup.style.display = 'block';
    } else {
      if (formSignup) formSignup.style.display = 'none';
      if (formLogin) formLogin.style.display = 'block';
    }
  };

  // Delegação de cliques para as abas
  $(document).on('click', '.auth-tab-btn', function(e) {
    e.preventDefault();
    var mode = $(this).attr('data-mode');
    window.switchAuthTab(mode);
  });

  $(document).ready(function() {
    // Mostrar / Ocultar Senha
    $(document).on('click', '.btn-toggle-pwd', function(e) {
      e.preventDefault();
      var targetId = $(this).data('target');
      var input = $('#' + targetId);
      var icon = $(this).find('i');
      if (input.attr('type') === 'password') {
        input.attr('type', 'text');
        icon.removeClass('fa-eye').addClass('fa-eye-slash');
      } else {
        input.attr('type', 'password');
        icon.removeClass('fa-eye-slash').addClass('fa-eye');
      }
    });

    // Submissão com tecla ENTER nos campos
    $(document).on('keypress', '#login_email, #login_password', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitLoginForm();
      }
    });

    $(document).on('keypress', '#signup_email, #signup_password, #signup_password_confirm', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitSignupForm();
      }
    });
  });

  // 3. Handlers Seguros do Shiny
  function registerShinyHandlers() {
    if (typeof Shiny === 'undefined' || !Shiny.addCustomMessageHandler) {
      setTimeout(registerShinyHandlers, 50);
      return;
    }

    // Handler de estado de autenticação (revelação ou bloqueio do app)
    Shiny.addCustomMessageHandler('set_auth_state', function(isAuth) {
      if (isAuth) {
        var btn = $('#btn_login_submit');
        if (btn.length) {
          btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Acesso autorizado!</span>');
        }
        $('body').addClass('authenticated');
        $('#auth_overlay_root').stop(true, true).fadeOut(250);
      } else {
        $('body').removeClass('authenticated');
        $('#auth_overlay_root').stop(true, true).fadeIn(200);
        var btn = $('#btn_login_submit');
        if (btn.length) {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');
        }
      }
    });

    // Salvar sessão persistente no localStorage
    Shiny.addCustomMessageHandler('save_auth_session', function(data) {
      if (data && (data.access_token || data.refresh_token)) {
        try {
          localStorage.setItem('quiin_auth_session', JSON.stringify(data));
        } catch(e) {}
      }
    });

    // Limpar sessão persistente no logout
    Shiny.addCustomMessageHandler('clear_auth_session', function(msg) {
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}
    });

    // Falha na restauração da sessão silenciosa
    Shiny.addCustomMessageHandler('restore_auth_failed', function(msg) {
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}
      $('#auth_restoring_state').hide();
      $('#auth_form_login').show();
      $('.auth-tabs-nav').show();
    });

    // Falha de login
    Shiny.addCustomMessageHandler('login_failed', function(data) {
      var btn = $('#btn_login_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');

      var msg = (data && data.message) ? data.message : 'Falha na autenticação. Verifique suas credenciais.';
      $('#auth_login_error_text').text(msg);
      $('#auth_login_error_box').stop(true, true).slideDown(150);
    });

    // Falha de cadastro
    Shiny.addCustomMessageHandler('signup_failed', function(data) {
      var btn = $('#btn_signup_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');

      var msg = (data && data.message) ? data.message : 'Falha no cadastro.';
      $('#auth_signup_error_text').text(msg);
      $('#auth_signup_error_box').stop(true, true).slideDown(150);
    });

    // Scroll para logs
    Shiny.addCustomMessageHandler('scroll-logs', function(msg) {
      setTimeout(function() {
        var log_elem = document.getElementById('modal_log_text');
        if (log_elem && log_elem.parentElement) {
          log_elem.parentElement.scrollTop = log_elem.parentElement.scrollHeight;
        }
      }, 50);
    });
  }

  registerShinyHandlers();

  // 4. Restauração Silenciosa ao Conectar no Shiny (SEM piscar ou apagar inputs)
  $(document).on('shiny:connected', function() {
    try {
      var saved = localStorage.getItem('quiin_auth_session');
      if (saved) {
        var sessionData = JSON.parse(saved);
        if (sessionData && (sessionData.access_token || sessionData.refresh_token)) {
          // Apenas envia a validação para o servidor silenciosamente
          Shiny.setInputValue('restore_auth_session', sessionData, {priority: 'event'});
        }
      }
    } catch(e) {}
  });

})();
