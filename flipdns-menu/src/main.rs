// Import
use std::fs; 
use std::io::Write;
use std::net::Ipv4Addr;

use std::path::Path;
use std::str::FromStr;

use cursive::align::HAlign;
use cursive::event::Key;
use cursive::view::{Resizable, Nameable};
use cursive::views::{Dialog, SelectView, TextView, LinearLayout,TextArea, ListView};
use cursive::Cursive;

use clap::Parser;




// Nous permet de traiter les parametres passer en ligne de commande
#[derive(Parser,Debug)]
#[command(author, version, about, long_about = None)]
struct Args {

    #[arg(long,help("le nom de l'interface de reseau"))]
    interface: String,
    // C'etait pour les cas si l'adresse est ipv6 
    // mais vue que pour le tp ce netait pas demander,
    // ca ne change rien. 
    #[arg(long,help("La version de l'adresse ip"))]
    ip_version: u8

}

// Choix proposer en version 4
const CHOICES_4: [&str;3] = [
    "OpenDns(208.67.222.222, 208.67.220.220)",
    "Cloudflare(1.1.1.1, 1.0.0.1)",
    "Personaliser"
];
// Choix proposer en version 6
const CHOICES_6: [&str;3] = [
    "OpenDns(2620:119:35::35, 2620:119:53::53)",
    "Cloudflare(2606:4700:4700::1111, 2606:4700:4700::1001)",
    "Personaliser"
];

const OPENDNS_4: &str = "208.67.222.222 208.67.220.220";
const OPENDNS_6: &str = "2620:119:35::35 2620:119:53::53";
const CLOUDFLARE_4: &str = "1.1.1.1 1.0.0.1";
const CLOUDFLARE_6: &str = "2606:4700:4700::64 2606:4700:4700::6400";

/// Entrepose les valeurs importante pendant l'execution
struct Data {

    inteface: String,
    ip_version: u8,
    output: String, 

}

fn main() {

    // Récupère les arguments passer en ligne de commande
    let args = Args::parse();
    // le constructeur de ncurses, cette instance est la partie centrale
    // de cette 'crate'. Elle nous permet en autre d'ajouter des vue a afficher au terminal
    let mut siv = cursive::default();

    /* 
    Propre a cette 'crate' et à la façon qu'il execute le programme, nous devons entreposer dans
    l'instance les valeurs qu'on souhaite acceder plus tard ou pendant l'execution principal.
    */
    siv.set_user_data(Data {
        inteface: args.interface,
        ip_version: args.ip_version,
        output: String::new(),
    });

    // Si l'utilisateur appuie sur le 'ESC', le TUI fermera
    siv.add_global_callback(Key::Esc, |s| { 
       
        s.user_data::<Data>().unwrap().output = String::new();
        s.quit(); 
    
    });

    // Affiche le menu principal
    show_select_menu(&mut siv);
    // Démarrer le TUI
    siv.run();

    
    // On arrive ici quand l'execution du tui est terminer. Autant que
    // si l'utilisateur quitte sans choisir une valeur ou non

    // si l'utilisateur n'a rien choisi (ESC a ete appuyer)
    // on le veut signaler au script qui exécutera ce programme
    if siv.user_data::<Data>().unwrap().output.is_empty() {
        std::process::exit(200);
    }


    let p = Path::new("C:\\Program Files\\FlipDNS\\data");

    // On doit s'assurer que le chemin n'existe pas deja, sinon un
    // erreur sera lever
    if !p.exists() {
        fs::create_dir(&p).unwrap();
    }

    // On veut s’assurer que le fichier existe avant de l'efface
    let np = p.join("output.txt");
    if np.exists() {
     
        fs::remove_file(&np).unwrap();
    } 

    // On crée le fichier et écrit la valeur choisi par l'utilisateur
    let mut file = fs::File::create(&np).unwrap();
    file.write_all(siv.user_data::<Data>().unwrap().output.as_bytes()).unwrap();

}


/// Fonction appeler quand l'utilisateur a fait sont choix 
fn choice_callback(siv: &mut Cursive, dns_conf:&str) {

    // efface l’écran 
    siv.pop_layer();

    siv.add_fullscreen_layer(TextView::new("Pour quitter, Appuyer sur la touche <Escape>").full_width());

    let ip_version = siv.user_data::<Data>().unwrap().ip_version;

    // traite les different choix possible 
    if dns_conf.contains("Cloudflare") {
        siv.add_layer(
            Dialog::around(TextView::new("Êtes vous sur de vouloir appliquer la configuration DNS de CloudFlare?"))
                .button("Oui", move|s| {
                    
                    if ip_version == 4 {
                        output_result(s, CLOUDFLARE_4);
                    } else {
                        output_result(s, CLOUDFLARE_6);
                    }
                    
                   
                })
                .button("Annulé", |s| show_select_menu(s) )
                .title("Avertissement")
        );
    } else if dns_conf.contains("OpenDns") {

        siv.pop_layer();
        siv.add_layer(
            Dialog::around(TextView::new("Êtes vous sur de vouloir appliquer la configuration DNS de OpenDNS?"))
                .button("Oui", move|s| {
                           
                    if ip_version == 4 {
                        output_result(s, OPENDNS_4);
                    } else {
                        output_result(s, OPENDNS_6);
                    }
                    

                })
                .button("Annulé", |s| show_select_menu(s) )
                .title("Avertissement")
        );
    } else if dns_conf.contains("Personnaliser"){

        show_input_dns(siv,None);

    }
    

}


/// Menu du choix personnaliser
fn show_input_dns(siv: &mut Cursive,errmsg:Option<&str>) {

    // efface l’écran
    siv.pop_layer();

    siv.add_fullscreen_layer(TextView::new("Pour quitter, Appuyer sur la touche <Escape>").full_width());
    
    let ip_version = siv.user_data::<Data>().unwrap().ip_version;

    let title = format!("Entrer des adresse IPV{} de serveur DNS",ip_version);

    siv.add_layer(
        Dialog::new()
            .title(title)
            .content(
                ListView::new()
                    .child("DNS 1",TextArea::new().with_name("DNS"))
                    .child("DNS 2 (optionnel)",TextArea::new().with_name("DNS")))
            .button("Annuler", |s| show_select_menu(s))
            .button("Appliquer",  move|s| {

                let mut results :Vec<String> = Vec::new();
                
                s.call_on_all_named("DNS", |view: &mut TextArea | {

                    let data = view.get_content().to_string();
                    if !data.is_empty() {
                        results.push(data);
                    }
                    
                });
 

                if !results.is_empty() {
                   
                   validate_dns_addr::<Ipv4Addr>(s, results) 
                } else {
                    show_input_dns(s, Some("Vous devez entrez au moins un adresse ip"));
                }


            })
                
    );
    
    if let Some(emsg) = errmsg {
        siv.add_layer(Dialog::info(emsg));
    }

}


/// S'assure que l’adresse personnaliser est valide
fn validate_dns_addr<I>(siv:&mut Cursive,results:Vec<String>) where I: FromStr {
    
    let mut valid = true;

    for i in 0..results.len(){ 

        if let Err(_) = results[i].parse::<I>() {
            show_input_dns(siv, Some(format!("Invalide adresse ip a la position {}",i+1).as_str()));
            valid = false;
        } 

    }

    if valid {
        siv.user_data::<Data>().unwrap().output = results.join(" ");

        siv.quit();
    }

}

/// Affiche le menu principal
fn show_select_menu(siv: &mut Cursive) {

    siv.pop_layer();

    let mut selection = SelectView::new()
        .h_align(HAlign::Center)
        .autojump();
    
    if siv.user_data::<Data>().unwrap().ip_version == 4 {
        selection.add_all_str(CHOICES_4);
    } else {
        selection.add_all_str(CHOICES_6);
    }
    
    
    selection.set_on_submit(choice_callback);

    let msg = format!(
        "La configuration DNS de l'interface {} est invalide. Veuillez choisir une nouvelle configuration",
        siv.user_data::<Data>().unwrap().inteface
    );

    let layout = LinearLayout::vertical()
        .child(TextView::new(msg))
        .child(selection);
    
    siv.add_fullscreen_layer(TextView::new("Pour quitter, Appuyer sur la touche <Escape>").full_width());
    siv.add_layer(Dialog::around(layout).title("FlipDNS"));

}

/// Entrepose un adresse dans la mémoire
fn output_result(siv: &mut Cursive, addrs:&str) {

    siv.with_user_data(|data: &mut Data| {
        data.output = addrs.to_string();   
    });

    siv.quit();

}
