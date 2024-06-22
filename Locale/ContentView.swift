import SwiftUI
import MapKit
import CoreLocation

struct Note: Identifiable {
    let id = UUID()
    var content: String
    var coordinate: CLLocationCoordinate2D
}

class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, ObservableObject {
    var mapView: MKMapView!
    let locationManager = CLLocationManager()
    @Published var notes: [Note] = []
    @Published var userLocation: CLLocationCoordinate2D?
    var initialLocationSet = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
        setupLocationManager()
    }
    
    func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        mapView.delegate = self
        mapView.showsUserLocation = true
    }
    
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
        print("Started updating location")
    }
    
    func addNote(content: String) {
        guard let userLocation = userLocation else {
            print("User location is nil, cannot add note")
            return
        }
        let newNote = Note(content: content, coordinate: userLocation)
        DispatchQueue.main.async {
            self.notes.append(newNote)
            self.addPinToMap(for: newNote)
        }
        print("Note added: \(content) at \(userLocation)")
    }
    
    func addPinToMap(for note: Note) {
        let annotation = MKPointAnnotation()
        annotation.coordinate = note.coordinate
        annotation.title = note.content
        DispatchQueue.main.async {
            self.mapView.addAnnotation(annotation)
            print("Pin added to map: \(note.content)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last?.coordinate else { return }
        DispatchQueue.main.async {
            self.userLocation = location
        }
        print("Location updated: \(location)")
        
        if !initialLocationSet {
            setRegion(for: location)
            initialLocationSet = true
            print("Initial location set")
        }
    }
    
    func setRegion(for location: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: location, latitudinalMeters: 500, longitudinalMeters: 500)
        DispatchQueue.main.async {
            self.mapView.setRegion(region, animated: true)
            print("Region set to: \(location)")
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
        
        let identifier = "NoteAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
        }
        
        annotationView?.markerTintColor = .red
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowNoteDetail"),
                object: nil,
                userInfo: ["noteContent": annotation.title as Any]
            )
        }
    }
}

class MapViewControllerHolder: ObservableObject {
    @Published var mapViewController: MapViewController?
}

struct MapViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var notes: [Note]
    @Binding var mapViewControllerHolder: MapViewControllerHolder
    
    func makeUIViewController(context: Context) -> MapViewController {
        let controller = MapViewController()
        controller.notes = notes
        DispatchQueue.main.async {
            self.mapViewControllerHolder.mapViewController = controller
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        uiViewController.notes = notes
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus?
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}

struct NoteDetail: Identifiable {
    let id = UUID()
    let content: String
}

struct ContentView: View {
    @State private var notes: [Note] = []
    @State private var isAddingNote = false
    @StateObject private var mapViewControllerHolder = MapViewControllerHolder()
    @State private var locationPermissionRequested = false
    @StateObject private var locationManager = LocationManager()
    @State private var selectedNote: NoteDetail?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            MapViewControllerRepresentable(notes: $notes, mapViewControllerHolder: .constant(mapViewControllerHolder))
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: addNoteAction) {
                        Image(systemName: "plus")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $isAddingNote) {
            AddNoteView(isPresented: $isAddingNote, onSave: { content in
                mapViewControllerHolder.mapViewController?.addNote(content: content)
            })
            .presentationDetents([.height(200)])
        }
        .popover(item: $selectedNote) { note in
            Text(note.content)
                .padding()
        }
        .onAppear(perform: setupLocationHandling)
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            checkLocationAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNoteDetail"))) { notification in
            if let noteContent = notification.userInfo?["noteContent"] as? String {
                DispatchQueue.main.async {
                    self.selectedNote = NoteDetail(content: noteContent)
                }
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func setupLocationHandling() {
        if !locationPermissionRequested {
            locationManager.requestLocationPermission()
            locationPermissionRequested = true
        }
        checkLocationAuthorization()
    }

    private func addNoteAction() {
        isAddingNote = true
        if let location = mapViewControllerHolder.mapViewController?.userLocation {
            mapViewControllerHolder.mapViewController?.setRegion(for: location)
        } else {
            showError("Unable to determine your location. Please ensure location services are enabled.")
        }
    }

    private func checkLocationAuthorization() {
        guard let authorizationStatus = locationManager.authorizationStatus else { return }
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            DispatchQueue.main.async {
                self.mapViewControllerHolder.mapViewController?.startUpdatingLocation()
                print("Location updates started")
            }
        case .notDetermined:
            locationManager.requestLocationPermission()
        case .restricted, .denied:
            showError("Location access was denied. Please enable location services for this app in Settings.")
        @unknown default:
            break
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showingErrorAlert = true
        }
    }
}

struct AddNoteView: View {
    @Binding var isPresented: Bool
    @State private var noteContent = ""
    var onSave: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Enter note", text: $noteContent)
            }
            .navigationBarTitle("Add Note", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Save") {
                    if !noteContent.isEmpty {
                        onSave(noteContent)
                        isPresented = false
                    }
                }
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
