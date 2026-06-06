%!TEX encoding = UTF-8

% Copyright (C) Julien Chiquet
%
% This program is free software: you can redistribute it and/or modify
%  it under the terms of the GNU General Public License as published by
%  the Free Software Foundation, either version 3 of the License, or
%  (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%  GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>

 %--------------------CLASSE LaTeX POUR LA REDACTION DE THESE-------------------%
% 
% Julien Chiquet
%
% Necessite au moins un fichier de style pour la these
% plus le fichier de style pour les pages administratives

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{these_gi}[2005/09/21 Classe pour ma]

%% Les differents styles 
\newif\if@styleben \@stylebenfalse

%% Chargement de la classe book, avec transfert d'options
\PassOptionsToClass{a4paper}{book}
\PassOptionsToClass{11pt}{book}
\PassOptionsToClass{twoside}{book}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{book}}
\DeclareOption{styleben}{\@stylebentrue}
\DeclareOption*{}
\ProcessOptions
\LoadClass{book}

 %--------------------PACKAGES STANDARD REQUIS-------------------%

% FONTS ET CARACTERES
\RequirePackage[T1]{fontenc}
\RequirePackage[utf8]{inputenc}
\RequirePackage[french]{babel}
\frenchspacing
\RequirePackage{eurosym}
\RequirePackage{xcolor}
\RequirePackage[toc,page]{appendix}

\RequirePackage{exscale,relsize}
\RequirePackage{stmaryrd}

% MODIF des compteurs.
\RequirePackage{remreset}
%\makeatletter \@addtoreset{chapter}{part} \makeatother

 %--------------------CHARGEMENT DE LA FEUILLE DE STYLE CHOISIE-------------------%
\if@styleben
  \RequirePackage{styleben}
\fi
