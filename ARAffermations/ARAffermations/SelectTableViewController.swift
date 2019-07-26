//
//  SelectTableViewController.swift
//  ARMultiuser
//
//  Created by Ari on 7/16/18.
//  Copyright © 2018 Logical Nonsene, LLC All rights reserved.
//

import UIKit

class SelectTableViewController: UITableViewController {
    var delegate: SelectTableViewControllerDelegate?
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Returns number of affermations as number of table view cells
        return Affirmations.list.count
    }

   
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        //Initalizes the cell with an affermation's text
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = Affirmations.list[indexPath.row]
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Sets the tapped affermation as the selected affermation in ViewController
        delegate?.selectAffermation(Affirmations.list[indexPath.row])
        self.navigationController?.popViewController(animated: true)
    }

}
protocol SelectTableViewControllerDelegate {
    func selectAffermation(_ affermation: String)
}
